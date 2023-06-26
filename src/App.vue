<script setup lang='ts'>
import { ref, onMounted } from 'vue'
import {
  nowInSec,
  RemoteVideoStream,
  SkyWayAuthToken,
  SkyWayContext,
  SkyWayRoom,
  SkyWayStreamFactory,
  uuidV4,
} from '@skyway-sdk/room'
import { appId, secret } from './env'
import * as Pitchfinder from 'pitchfinder'

const token = new SkyWayAuthToken({
  jti: uuidV4(),
  iat: nowInSec(),
  exp: nowInSec() + 60 * 60 * 24,
  scope: {
    app: {
      id: appId,
      turn: true,
      actions: ['read'],
      channels: [
        {
          id: '*',
          name: '*',
          actions: ['write'],
          members: [
            {
              id: '*',
              name: '*',
              actions: ['write'],
              publication: {
                actions: ['write'],
              },
              subscription: {
                actions: ['write'],
              },
            },
          ],
          sfuBots: [
            {
              actions: ['write'],
              forwardings: [
                {
                  actions: ['write'],
                },
              ],
            },
          ],
        },
      ],
    },
  },
}).encode(secret)

// ドレミファソラシドの12音符（音名）
const notes = [
  'ラ',
  'ラ#',
  'シ',
  'ド',
  'ド#',
  'レ',
  'レ#',
  'ミ',
  'ファ',
  'ファ#',
  'ソ',
  'ソ#'
]

// 12平均律の周波数
const frequencies = [
  440.00, // ラ
  466.16, // ラ#（高）
  493.88, // シ
  261.63, // ド
  277.18, // ド#（高）
  293.66, // レ
  311.13, // レ#（高）
  329.63, // ミ
  349.23, // ファ
  369.99, // ファ#（高）
  392.00, // ソ
  415.30 // ソ#（高）
]

const myVideo = ref(null)
const myAudio = ref(null)

const localVideo = ref(null)
const remoteVideoArea = ref(null)
const remoteAudioArea = ref(null)

const myId = ref('')
const roomName = ref('')
const analyzedAudio = ref('')
const audioPich = ref('')
const baseFrequency = ref(440)

const isAbsolutePitch = ref(false)

onMounted(async () => {
  // 自分の音声と映像を取得
  const { audio, video } = await SkyWayStreamFactory.createMicrophoneAudioAndCameraStream()
  myVideo.value = video
  myAudio.value = audio

  // 自分の映像を表示
  myVideo.value.attach(localVideo.value)
  await localVideo.value.play()
})

const join = async () => {
  if (roomName.value === '') return

  // 特定のRoomに入室する
  const context = await SkyWayContext.Create(token)
  const room = await SkyWayRoom.FindOrCreate(context, {
    type: 'p2p',
    name: roomName.value,
  })
  const me = await room.join()
  myId.value = me.id

  // 自分の映像と音声を公開する
  await me.publish(myVideo.value)
  await me.publish(myAudio.value)

  // 他のユーザーがいた・入室してきた時の処理
  const subscribeAndAttach = async (publication: any) => {
    if (publication.publisher.id === me.id) return

    const { stream } = await me.subscribe<RemoteVideoStream>(
      publication.id
    )

    // DOMに直接videoとaudioのelementを追加する
    let newMedia
    switch (stream.track.kind) {
      case 'video':
        newMedia = document.createElement('video')
        newMedia.width = 300
        newMedia.playsInline = true
        newMedia.autoplay = true

        stream.attach(newMedia)
        remoteVideoArea.value.appendChild(newMedia)
        break
      case 'audio':
        newMedia = document.createElement('audio')
        newMedia.controls = true
        newMedia.autoplay = true

        // MediaStreamTrackをMediaStreamに変換
        const mediaStream = new MediaStream([stream.track])
        const audioContext = new AudioContext()
        // MediaStreamからオーディオソースノードを作成
        const sourceNode = audioContext.createMediaStreamSource(mediaStream)
        // モノラルのスクリプトプロセッサーノードを作成
        const scriptNode = audioContext.createScriptProcessor(2048, 1, 1)

        // 処理したオーディオデータが実際に再生させる
        sourceNode.connect(scriptNode)
        scriptNode.connect(audioContext.destination)

        // オーディオデータが一定のバッファサイズになったらコールバックする
        scriptNode.onaudioprocess = (event) => {
          // オーディオデータを取り出す（モノラル）
          const audioData = event.inputBuffer.getChannelData(0)
          // pitchfinderで音声解析
          const detectPitch = Pitchfinder.AMDF()
          const pitch = detectPitch(audioData)

          // 解析できた音があった場合画面に表示する
          if (pitch) {
            audioPich.value = Math.round(pitch)
            const pitchIndex = pitchToIndex(audioPich.value)
            analyzedAudio.value = notes[pitchIndex]

            if (isAbsolutePitch.value) {
              // オシレーターノードを作成
              const oscillator = audioContext.createOscillator()
              oscillator.frequency.value = frequencies[pitchIndex]

              // 出力先に接続してオシレーターを再生する
              oscillator.connect(audioContext.destination)
              oscillator.start()

              // オシレーターを0.3秒だけ再生して停止する
              oscillator.stop(audioContext.currentTime + 0.3)
            }
          } else {
            audioPich.value = ''
            analyzedAudio.value = ''
          }
        }

        stream.attach(newMedia)
        remoteAudioArea.value.appendChild(newMedia)
        break
      default:
        return
    }
  }

  // 入室した部屋で公開されている映像・音声があった時に実行
  room.publications.forEach(subscribeAndAttach)
  // 別のユーザーが新しく映像・音声を公開した時にも実行
  room.onStreamPublished.add((e: any) => subscribeAndAttach(e.publication))
}

// 基準の周波数と測定したピッチから12音符を判定する
const pitchToIndex = (pitch: number) => {
  // ラから測定した音までの半音の数を計算
  const semitone = Math.round(12 * Math.log2(pitch / baseFrequency.value))
  // ラからの半音の数を12で割った余りを計算
  // 結果となる余りはマイナスになる事があるので、それに更に12を足して12で割った余りを出す事で「0~11」の値を出す
  return (semitone % 12 + 12) % 12
}
</script>

<template>
  <div>
    <div>ID: <span>{{ myId }}</span></div>
    <div class="my-data">
      <video ref="localVideo" muted playsinline class="local-video" />
      <div class="analyzed-audios">
        <div>{{ audioPich }}</div>
        <div class="analyzed-audio">{{ analyzedAudio }}</div>
      </div>
      <div class="toggles">
        <label for="base-frequency" class="frequency-label">基準となる「ラ」の周波数</label>
        <input v-model="baseFrequency" type="text" class="base-frequency" id="base-frequency" />
        <label for="absolute-pitch" class="toggle-label">標準音階モード</label>
        <input v-model="isAbsolutePitch" type="checkbox" class="toggle" id="absolute-pitch" />
        <div class="toggle-button" :class="{ 'active': isAbsolutePitch }" @click="isAbsolutePitch = !isAbsolutePitch" />
      </div>
    </div>
    <div class="room-name">
      Room Name:
      <div v-if="!myId">
        <input v-model="roomName" type="text" />
        <button @click="join">Join</button>
      </div>
      <div v-else>{{roomName}}</div>
    </div>
    <div ref="remoteVideoArea" class="remote-videos" />
    <div ref="remoteAudioArea" class="remote-audios" />
  </div>
</template>

<style scoped>
.room-name {
  display: flex;
  justify-content: center;
  align-items: center;
  padding: 8px;
  gap: 8px;
}

.local-video {
  width: 300px;
}

.remote-videos {
  display: grid;
  grid-template-columns: 300px;
  grid-auto-flow: column;
  gap: 8px;
}

.remote-audios {
  display: grid;
  grid-template-columns: 300px;
  grid-auto-flow: column;
  gap: 8px;
}

.my-data {
  display: flex;
  gap: 16px;
}

.analyzed-audios {
  width: 200px;
  border: 1px solid #ffffff;
  display: grid;
  grid-template-rows: 24px 1fr;
  align-items: center;
}

.base-frequency {
  margin-bottom: 16px;
  text-align: center;
}

.analyzed-audio {
  font-size: 64px;
}

.toggles {
  margin: auto;
  padding: 8px;
}

.frequency-label {
  display: block;
}

.toggle-label {
  display: block;
  font-weight: bold;
  margin-bottom: 8px;
}

.toggle {
  display: none;
}

.toggle-button {
  display: inline-block;
  position: relative;
  width: 80px;
  height: 40px;
  border-radius: 40px;
  background-color: #dddddd;
  cursor: pointer;
  transition: background-color 0.3s;
}

.toggle-button.active {
  background-color: #4bd865;
}

.toggle-button::after {
  position: absolute;
  content: '';
  top: 0;
  left: 0;
  width: 40px;
  height: 40px;
  border-radius: 50%;
  background-color: #ffffff;
  box-shadow: 0 0 5px rgb(0 0 0 / 20%);
  transition: left 0.3s;
}

.toggle-button.active::after {
  left: 40px;
}
</style>

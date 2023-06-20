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
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
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

        // オーディオデータの入力バッファが供給されるたびにコールバック
        scriptNode.onaudioprocess = (event) => {
          // オーディオデータを取り出す（モノラル）
          const audioData = event.inputBuffer.getChannelData(0)
          // pitchfinderで音声解析
          const detectPitch = Pitchfinder.YIN()
          const pitch = detectPitch(audioData)

          // 解析できた音があった場合画面に表示する
          if (pitch) {
            audioPich.value = Math.round(pitch)
            analyzedAudio.value = pitchToNote(audioPich.value)
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

// 音符にマッピングする関数
const pitchToNote = (pitch: number) => {
  const noteIndex = pitch % notes.length
  // 音符の文字列を返す
  return notes[noteIndex]
}
</script>

<template>
  <div>
    <div>ID: <span>{{ myId }}</span></div>
    <div class="my-data">
      <video ref="localVideo" muted playsinline class="local-video" />
      <div class="analyzed-audios">
        <div class="audio-pitch">{{ audioPich }}</div>
        <div class="analyzed-audio">{{ analyzedAudio }}</div>
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
}

.audio-pitch{
  margin-bottom: 8px;
}

.analyzed-audio {
  font-size: 128px;
}
</style>

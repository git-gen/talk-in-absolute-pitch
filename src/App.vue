<script setup lang="ts">
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
import { appId, secret } from './env.ts'

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

const myVideo = ref(null)
const myAudio = ref(null)

const localVideo = ref(null)
const remoteVideoArea = ref(null)
const remoteAudioArea = ref(null)

const myId = ref('')
const roomName = ref('')

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
</script>

<template>
  <div>
    <div>ID: <span>{{ myId }}</span></div>
    <video ref="localVideo" muted playsinline class="local-video" />
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
</style>

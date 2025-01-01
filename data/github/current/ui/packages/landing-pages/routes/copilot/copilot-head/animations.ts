import type {Group, Material, Mesh} from 'three'
import type {cameraDetails} from './utils/timeline'
import {lerp} from './utils/math'
import common from './common'
import controls from './controls'
import mouseMng from './mouseMng'
import Timeline from './utils/timeline'
import {Vector3} from 'three'

export default class Animations {
  animationGroup: Group
  group: Group
  goggleGroup: Group
  faceGroup: Group
  eyesMeshes: {left: Mesh | null; right: Mesh | null}
  isFinishedEntrance: boolean
  isPlayingClickAnim: boolean
  isBlinking: boolean
  blinkTimer: NodeJS.Timeout
  clickAction: string | undefined
  isWinking: boolean

  constructor({
    group,
    animationGroup,
    goggleGroup,
    faceGroup,
    eyesMeshes,
  }: {
    group: Group
    animationGroup: Group
    goggleGroup: Group
    faceGroup: Group
    eyesMeshes: {left: Mesh | null; right: Mesh | null}
  }) {
    this.group = group
    this.goggleGroup = goggleGroup
    this.faceGroup = faceGroup
    this.eyesMeshes = eyesMeshes
    this.animationGroup = animationGroup

    this.isFinishedEntrance = false
    this.isPlayingClickAnim = false

    this.isBlinking = false

    this.init()
  }

  init() {
    setTimeout(() => {
      this.createEntrance()
    }, 450)
  }

  createEntrance() {
    const camera: cameraDetails = {
      radius: 11,
      radian: Math.PI * 2,
      lookat: new Vector3(0, 0, 0),
    }
    const tl = new Timeline({
      onComplete: () => {
        this.isFinishedEntrance = true
        this.createBlinkEyes()
      },
      easing: 'linear',
      onUpdate: () => {
        const x = Math.sin(camera.radian) * camera.radius
        const z = Math.cos(camera.radian) * camera.radius
        common.camera.position.set(x, 0, z)
        common.camera.lookAt(camera.lookat)
      },
    })
    this.group.visible = true
    tl.to(this.group.scale, 1000, {x: 1, y: 1, z: 1, easing: 'easeOutBack'}, 0).to(
      camera,
      1500,
      {radian: 0, easing: 'easeOutBack'},
      0,
    )
    tl.start()
  }

  createBlinkEyes() {
    this.isBlinking = true
    const tl = new Timeline({
      onComplete: () => {
        this.isBlinking = false
        const delay = lerp(2, 6, Math.random()) * 1000
        this.blinkTimer = setTimeout(() => {
          this.createBlinkEyes()
        }, delay)
      },
      easing: 'easeOutCubic',
    })
    const type = Math.random() < 0.8 ? 'blinkType1' : 'blinkType2'

    const bs = controls.params.blinkingSpeed / 1000
    const leftEye = this.eyesMeshes.left
    const rightEye = this.eyesMeshes.right
    const eyesScale = [leftEye ? leftEye.scale : 1, rightEye ? rightEye.scale : 1]

    if (type === 'blinkType1') {
      tl.to(eyesScale, 0.1 / bs, {y: 0.1}, 0)
        .to(eyesScale, 0.3 / bs, {y: 1}, 0.2 / bs)
        .start()
    } else {
      tl.to(eyesScale, 0.1 / bs, {y: 0.1}, 0)
        .to(eyesScale, 0.2 / bs, {y: 1}, 0.2 / bs)
        .to(eyesScale, 0.3 / bs, {y: 0.1})
        .to(eyesScale, 0.3 / bs, {y: 1})
        .start()
    }
  }

  createClickAnimation() {
    if (!this.isFinishedEntrance) return
    if (this.isPlayingClickAnim) return
    switch (controls.params.clickAction) {
      case 'random':
        this.clickAction = controls.getRandomAnim(this.isBlinking)
        break
      default:
        this.clickAction = controls.params.clickAction
    }

    switch (this.clickAction) {
      case 'wink':
        if (this.isBlinking) return
        if (this.blinkTimer) clearTimeout(this.blinkTimer)
        this.createWink()
        break
      case 'jump1':
      case 'jump2':
      case 'jump3':
        this.createJump()
        break
      case 'shake':
        if (this.isBlinking) return
        if (this.blinkTimer) clearTimeout(this.blinkTimer)
        this.createShake()
        break
    }
  }

  createWink() {
    if (this.isPlayingClickAnim) return
    this.isPlayingClickAnim = true

    const tl = new Timeline({
      onComplete: () => {
        this.isPlayingClickAnim = false
        const delay = lerp(1, 4, Math.random()) * 1000
        this.blinkTimer = setTimeout(() => {
          this.createBlinkEyes()
        }, delay)
      },
      easing: 'easeOutCubic',
    })

    const isLeft = mouseMng.pos.current.x > 0.0

    const delay = 250

    const eye = isLeft ? this.eyesMeshes.left : this.eyesMeshes.right
    const eyeScale = eye ? eye.scale : new Vector3(1, 1, 1)
    const rot = isLeft ? -0.4 : 0.4
    const aGR = [this.animationGroup.rotation]
    const gs = [this.animationGroup.scale]
    const uniforms = eye ? (eye.material as Material).userData.uniforms : null

    tl.to(eyeScale, 100, {y: 0.1}, delay)
      .to(eyeScale, 200, {y: 1}, delay + 400)
      .to(uniforms.uWink, 100, {value: 1}, delay)
      .to(uniforms.uWink, 100, {value: 0}, delay + 400)

    const puyoDuration = 200

    tl.to(gs, puyoDuration, {x: 1.03, y: 0.97}, 0)
      .to(gs, puyoDuration * 2, {x: 1.0, y: 1.0}, puyoDuration)
      .to(gs, puyoDuration * 1, {x: 1.02, y: 0.98}, puyoDuration * 3)
      .to(gs, puyoDuration * 2, {x: 1, y: 1}, puyoDuration * 4)
      .to(aGR, delay, {z: -rot * 0.2}, 0)
      .to(aGR, 400, {z: rot}, delay)
      .to(aGR, 600, {z: 0}, 500)
      .start()
  }

  createJump() {
    if (this.isPlayingClickAnim) return
    this.isPlayingClickAnim = true

    if (this.clickAction !== 'jump1') {
      this.createRotating()
    }

    const tl = new Timeline({
      onComplete: () => {
        if (this.clickAction === 'jump1') {
          this.isPlayingClickAnim = false
        }
      },
      easing: 'easeOutCubic',
    })

    const s = 1000
    const gs = this.animationGroup.scale
    const ag = this.animationGroup.position
    const aGR = this.animationGroup.rotation

    tl.to(gs, 0.2 * s, {y: 0.95, x: 1.05}, 0)
      .to(gs, 0.1 * s, {y: 1.05, x: 0.95})
      .to(gs, 0.2 * s, {y: 1, x: 1})
      .to(gs, 0.2 * s, {y: 1.03, x: 0.97})
      .to(gs, 0.2 * s, {y: 0.97, x: 1.03})
      .to(gs, 0.3 * s, {y: 1, x: 1})
      .to(aGR, 200, {x: 0.2}, 0)
      .to(aGR, 500, {x: -0.1}, 200)
      .to(aGR, 300, {x: 0.0}, 700)
      .to(ag, 0.2 * s, {y: -0.2}, 0)
      .to(ag, 0.3 * s, {y: 1.5}, 0.2 * s)
      .to(ag, 0.3 * s, {y: -0.2, easing: 'easeInQuad'}, 0.5 * s)
      .to(ag, 0.2 * s, {y: 0}, 0.8 * s)

    const gGP = [this.goggleGroup.position]
    switch (this.clickAction) {
      case 'jump2':
      case 'jump3':
        // goggle
        tl.to(gGP, 0.4 * s, {y: 0.6}, 0.3 * s)
          .to(gGP, 0.4 * s, {y: 0.0}, 0.7 * s)
          .start()
        break
      default:
        tl.start()
        break
    }
  }

  createRotating() {
    const data = {
      anim_rotating: this.goggleGroup.userData.rotateX.anim_rotating,
    }

    const s = 1000

    const tl = new Timeline({
      onComplete: () => {
        this.isPlayingClickAnim = false
      },
      onUpdate: () => {
        this.goggleGroup.userData.rotateX.anim_rotating = data.anim_rotating
      },
      easing: 'easeOutCubic',
    })

    let rotateRange = 0

    const rotateSetY = []
    const rotateSetZ = []

    let rotTimingY = 0
    let rotTimingZ = 100
    for (let i = 0; i < 4; i++) {
      const r = Math.random()

      let offsetY = lerp(0.1, 0.3, r)
      const durationY = lerp(150, 200, r)

      let offsetZ = lerp(0.05, 0.1, r)
      const durationZ = durationY

      if (i === 3) {
        offsetZ = 0
      }

      if (i % 2 === 0) {
        offsetY *= -1
        offsetZ *= -1
      }

      rotateSetY[i] = {
        offset: offsetY,
        duration: durationY,
        delay: rotTimingY,
      }

      rotateSetZ[i] = {
        offset: offsetZ,
        duration: durationZ,
        delay: rotTimingZ,
      }

      rotTimingY += durationY
      rotTimingZ += durationZ
    }

    const aGR = [this.animationGroup.rotation]

    if (this.clickAction === 'jump3') {
      rotateRange = Math.PI * 2
      tl.to(aGR, 200, {z: 0.1}, 0)
        .to(aGR, 200, {z: 0}, 200)
        .to(aGR, 500, {y: Math.PI, easing: 'easeInCubic'}, 0)
        .to(aGR, 700, {y: rotateRange, easing: 'easeOutCubic'}, 500)
        .to(aGR, 400, {z: -0.1}, 600)
        .to(aGR, 300, {z: 0}, 1000)
    }

    for (const item of rotateSetY) {
      tl.to(aGR, item.duration, {y: rotateRange + item.offset}, item.delay + 1300)
    }

    tl.to(aGR, 300, {
      y: rotateRange,
      onComplete: () => {
        this.animationGroup.rotation.y = 0
      },
    })

    for (const item of rotateSetZ) {
      tl.to(aGR, item.duration, {z: item.offset, easing: 'easeOutQuad'}, item.delay + 1300)
    }

    tl.to([data], 0.7 * s, {anim_rotating: 0.35}, 0.6 * s)
      .to([data], 0.5 * s, {anim_rotating: 0}, 1.5 * s)
      .start()
  }

  createShake() {
    if (this.isPlayingClickAnim) return
    this.isPlayingClickAnim = true

    const tl = new Timeline({
      onComplete: () => {
        this.isPlayingClickAnim = false
        const delay = lerp(1, 4, Math.random()) * 1000
        this.blinkTimer = setTimeout(() => {
          this.createBlinkEyes()
        }, delay)
      },
      easing: 'easeOutQuad',
    })

    const aGR = this.animationGroup.rotation
    const d = 200

    const leftEye = this.eyesMeshes.left
    const rightEye = this.eyesMeshes.right
    const eyeScales = [leftEye ? leftEye.scale : new Vector3(1, 1, 1), rightEye ? rightEye.scale : new Vector3(1, 1, 1)]
    const uWink = [
      (leftEye!.material as Material).userData.uniforms.uWink,
      (rightEye!.material as Material).userData.uniforms.uWink,
    ]
    const gs = [this.animationGroup.scale]

    const rotateSet = []
    for (let i = 0; i < 6; i++) {
      const r = Math.random()
      let offset = lerp(0.1, 0.2, r)
      const duration = lerp(150, 200, r)
      if (i % 2 === 0) {
        offset *= -1
      }

      rotateSet[i] = {
        offset,
        duration,
      }
    }

    for (const item of rotateSet) {
      tl.to(aGR, item.duration, {y: item.offset})
    }

    tl.to(aGR, d, {y: 0.0})
      .to(aGR, 1000, {x: -0.3}, 0)
      .to(aGR, 500, {x: 0}, 1000)
      .to(eyeScales, 100, {y: 0.35}, 0)
      .to(eyeScales, 250, {y: 1}, 1000)
      .to(uWink, 100, {value: 1.2}, 0)
      .to(uWink, 100, {value: 0}, 1000)

    const puyoDuration = 200

    tl.to(gs, puyoDuration, {x: 1.02, y: 0.98}, 0)
      .to(gs, puyoDuration * 2, {x: 1.0, y: 1.0}, puyoDuration)
      .to(gs, puyoDuration * 1, {x: 1.02, y: 0.98}, puyoDuration * 3)
      .to(gs, puyoDuration * 2, {x: 1, y: 1}, puyoDuration * 4)
      .start()
  }

  resize() {}
  update() {}
}

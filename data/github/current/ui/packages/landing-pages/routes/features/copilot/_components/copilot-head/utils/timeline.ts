import type {Euler, Vector3} from 'three'
import {easings} from './easing'

interface Animation {
  datas: Euler[] | Vector3[] | unknown[] | cameraDetails[]
  duration: number
  easing: string
  onComplete?: () => void
  onUpdate?: () => void
  values: arrangedValues[]
  delay: number
  properties: AnimationProperties
  isStarted: boolean
  isLast: boolean
  isFinished: boolean
}

interface arrangedValues {
  key: string
  start: number[] | unknown[]
  current: unknown[]
  end: number[] | unknown[]
}

export interface cameraDetails {
  radius: number
  radian: number
  lookat: Vector3
}

interface AnimationProperties {
  y?: number
  x?: number
  z?: number
  value?: number
  anim_rotating?: number
  radian?: number
  onComplete?: () => void
  easing?: string
  onUpdate?: () => void
}

export default class Timeline {
  animations: Animation[]
  easing: string
  options: {onComplete: () => void; easing: string; onUpdate?: () => void}
  onUpdate: () => void
  onComplete: () => void
  isFinished: boolean
  lastIndex: number
  isWindowFocus: boolean
  startTime: Date
  oldTime: Date
  time: number

  constructor(options: {onComplete: () => void; easing: string; onUpdate?: () => void}) {
    this.easing = options.easing || 'linear'
    this.options = options
    this.onUpdate = options.onUpdate || function () {}
    this.onComplete = options.onComplete || function () {}

    this.isFinished = false

    this.lastIndex = 0

    this.isWindowFocus = true

    this.animations = []
    this.startTime = new Date()
    this.oldTime = new Date()
    this.time = 0
  }

  to(
    _datas: unknown[] | Vector3 | Euler | cameraDetails,
    duration: number,
    properties: AnimationProperties,
    _delay?: number | 0,
  ) {
    let delay = 0
    if (_delay !== undefined && !isNaN(_delay)) {
      delay = _delay
    } else {
      if (this.animations.length > 0) {
        const prevAnim = this.animations[this.animations.length - 1]
        if (prevAnim) delay = prevAnim.duration + prevAnim.delay
      } else {
        delay = 0
      }
    }

    const values: arrangedValues[] = []
    let datas

    if (Array.isArray(_datas)) {
      datas = _datas
    } else {
      datas = [_datas]
    }

    this.animations.push({
      datas,
      duration,
      easing: properties.easing || this.easing,
      onComplete: properties.onComplete,
      onUpdate: properties.onUpdate,
      values,
      delay,
      properties,
      isStarted: false,
      isLast: false,
      isFinished: false,
    })

    let longestTime = 0
    let index = 0
    for (const animation of this.animations) {
      const t = animation.duration + animation.delay
      if (longestTime < t) {
        longestTime = t
        this.lastIndex = index
      }

      animation.isLast = false
      index++
    }

    return this
  }

  start() {
    this.startTime = new Date()
    this.oldTime = new Date()
    const lastAnimation = this.animations[this.lastIndex]
    if (lastAnimation) lastAnimation.isLast = true
    window.addEventListener('visibilitychange', this.onVisiblitychange)

    this.animate()
  }

  animate = () => {
    const currentTime = new Date()

    if (!this.isWindowFocus) {
      this.oldTime = currentTime
    }

    const delta = currentTime.getTime() - this.oldTime.getTime()
    this.time += delta

    this.oldTime = currentTime

    for (const animation of this.animations) {
      const {datas, duration, easing, values, delay} = animation

      if (this.time > delay && !animation.isFinished) {
        if (!animation.isStarted) {
          animation.isStarted = true
          this.arrangeDatas(animation)
        }
        const startTime = 0
        const endTime = duration

        let progress = this.calcProgress(startTime, endTime, this.time - delay)
        const easingFunc = easings[easing]
        if (easingFunc !== undefined) progress = easingFunc(progress)

        for (let i = 0; i < values.length; i++) {
          const v = values[i]
          for (let j = 0; j < datas.length; j++) {
            const d = datas[j]
            if (v !== undefined) {
              v.current[j] = this.calcLerp(v.start[j]! as number, v.end[j]! as number, progress)
              if (typeof d === 'object' && d !== null) {
                d[v.key as keyof typeof d] = v.current[j] as never
              }
            }
          }
        }

        if (animation.onUpdate) {
          animation.onUpdate()
          return
        }

        if (progress === 1) {
          animation.isFinished = true
          if (animation.onComplete) animation.onComplete()
          if (animation.isLast) {
            this.isFinished = true
          }
        }
      }
    }

    if (!this.isFinished) {
      this.onUpdate()
      requestAnimationFrame(this.animate)
    } else {
      window.removeEventListener('visibilitychange', this.onVisiblitychange)
      this.onComplete()
    }
  }

  arrangeDatas(animation: Animation) {
    const {properties, datas, values} = animation
    for (const key in properties) {
      let index = 0
      const start: unknown[] = []
      const current: unknown[] = []
      const end = []
      switch (key) {
        case 'easing':
        case 'onComplete':
        case 'onUpdate':
          break
        default:
          for (const item of datas) {
            if (item !== null && typeof item === 'object') {
              start[index] = item[key as keyof typeof item]
              current[index] = item[key as keyof typeof item]
              end[index] = properties[key as keyof typeof properties]
              index++
            }
          }

          values.push({
            key,
            start,
            current,
            end,
          })
          break
      }
    }
  }

  calcProgress(start: number, end: number, currentTime: number) {
    const p = (currentTime - start) / (end - start)
    return Math.max(0, Math.min(1, p))
  }

  calcLerp(start: number, end: number, progress: number) {
    return start + (end - start) * progress
  }

  onVisiblitychange = () => {
    if (document.visibilityState === 'visible') {
      // console.log("focus");
      this.isWindowFocus = true
    } else {
      // console.log("blur");
      this.isWindowFocus = false
    }
  }
}

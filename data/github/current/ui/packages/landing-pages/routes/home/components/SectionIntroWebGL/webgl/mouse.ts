import {Vector2} from 'three'
import type Common from './common'

export default class Mouse {
  originalPos: Vector2
  pos: {target: Vector2; current: Vector2; current2: Vector2}
  common?: Common
  constructor(common: Common) {
    this.common = common
    this.originalPos = new Vector2()
    this.pos = {
      target: new Vector2(0, 0),
      current: new Vector2(0, 0),
      current2: new Vector2(0, 0),
    }
  }

  init() {
    window.addEventListener('mousemove', event => {
      if (!this.common) return
      let x =
        (event.clientX - this.common?.wrapperOffset.x + this.common?.mascotAreaOffset.x) / this.common?.screenSize.x
      x = (x - 0.5) * 2.0
      let y =
        (event.clientY - this.common?.wrapperOffset.y + this.common?.mascotAreaOffset.y) / this.common?.screenSize.y
      y = (0.5 - y) * 2.0

      x = Math.max(-1, Math.min(1, x))
      y = Math.max(-1, Math.min(1, y))

      this.updateMousePos(x, y)
    })
  }

  updateMousePos(x: number, y: number) {
    this.pos.target.set(x, y)
  }

  resize() {}

  update() {
    if (!this.common) return
    this.pos.current.lerp(this.pos.target, this.common.getEase(2))
    this.pos.current2.lerp(this.pos.target, this.common.getEase(1.5))
  }
}

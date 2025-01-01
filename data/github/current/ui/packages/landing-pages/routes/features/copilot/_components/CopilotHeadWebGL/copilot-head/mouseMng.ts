// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {Vector2} from 'three'
import common from './common'

class MouseMng {
  originalPos: Vector2
  mousemoveFuncs: Array<() => void>
  pos: {target: Vector2; current: Vector2; current2: Vector2}

  constructor() {
    this.originalPos = new Vector2()

    this.mousemoveFuncs = []
    this.pos = {
      target: new Vector2(-3, -3),
      current: new Vector2(-3, -3),
      current2: new Vector2(-3, -3),
    }
  }

  init() {
    window.addEventListener('mousemove', event => {
      let x = (event.clientX - common.wrapperOffset.x) / common.sizes.x
      x = (x - 0.5) * 2.0
      let y = (event.clientY - common.wrapperOffset.y) / common.sizes.y
      y = (0.5 - y) * 2.0

      this.updateMousePos(x, y)
    })

    // eslint-disable-next-line github/require-passive-events
    window.addEventListener('touchstart', event => {
      if (event.touches[0]) {
        let x = (event.touches[0].clientX - common.wrapperOffset.x) / common.sizes.x
        x = (x - 0.5) * 2.0
        let y = (event.touches[0].clientY - common.wrapperOffset.y) / common.sizes.y
        y = (0.5 - y) * 2.0

        this.updateMousePos(x, y)
      }
    })
  }

  updateMousePos(x: number, y: number) {
    this.pos.target.set(x, y)

    for (const func of this.mousemoveFuncs) {
      func()
    }
  }

  addMousemoveFunc(func: () => void) {
    this.mousemoveFuncs.push(func)
  }

  resize() {}

  update() {
    this.pos.current.lerp(this.pos.target, common.getEase(2))
    this.pos.current2.lerp(this.pos.target, common.getEase(1.5))
  }
}

const mouseMng = new MouseMng()
export default mouseMng

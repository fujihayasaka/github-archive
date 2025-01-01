import type Assets from '../../../webgl-utils/assets'
import Common from './common'
import MascotObj from './mascot-obj'
import ShieldObj from './shield-obj'

import {catTextureData} from './params/cat'
import {copilotTextureData} from './params/copilot'
import {duckTextureData} from './params/duck'
import type {MascotType} from '../mascot-type'
import Mouse from './mouse'

// import {MathUtils} from 'three'

export default class Artwork {
  private $wrapper: HTMLElement
  private $canvas: HTMLCanvasElement
  private $mascot: HTMLElement
  private assets: Assets
  private common: Common = new Common()
  private name: MascotType['name']
  private mascot: MascotObj
  private shield: ShieldObj
  private mouse: Mouse = new Mouse(this.common)
  private isFirstShow = false
  private isMascotOnly?: boolean
  private isLoaded: boolean = false

  constructor(
    $wrapper: HTMLElement,
    $canvas: HTMLCanvasElement,
    $mascot: HTMLElement,
    name: MascotType['name'],
    isMascotOnly: boolean | undefined,
    isReducedMotion: boolean,
    assets: Assets,
  ) {
    this.$wrapper = $wrapper
    this.$canvas = $canvas
    this.$mascot = $mascot
    this.name = name
    this.isMascotOnly = isMascotOnly
    this.common.isReducedMotion = isReducedMotion

    if (!this.isMascotOnly) {
      if (this.common.isReducedMotion) {
        this.isFirstShow = true
      }
    }
    this.assets = assets
    switch (this.name) {
      case 'mona':
        this.mascot = new MascotObj('cat', this.common, this.assets, catTextureData)
        this.common.scene.add(this.mascot.group)
        break
      case 'copilot':
        this.mascot = new MascotObj('copilot', this.common, this.assets, copilotTextureData)
        this.common.scene.add(this.mascot.group)
        break
      case 'ducky':
        this.mascot = new MascotObj('duck', this.common, this.assets, duckTextureData)
        this.common.scene.add(this.mascot.group)
        break
      case 'shield':
        this.shield = new ShieldObj(this.common, this.assets)

        this.common.scene.add(this.shield.group)
        break

      default:
        break
    }

    if (this.isMascotOnly) {
      if (this.mascot) this.mascot.group.scale.set(9, 9, 9)
      if (this.shield) this.shield.group.scale.set(9, 9, 9)
    }
    this.common.init({
      $wrapper: this.$wrapper,
      $canvas: this.$canvas,
      $mascot: this.$mascot,
    })
    this.mouse.init()

    this.common.camera.position.set(0, 0.0, 2.2)
    this.common.camera.lookAt(this.common.scene.position)
  }

  toggleVisibility(isVisible: boolean, isReduceMotion: boolean): void {
    if (isVisible && !this.isFirstShow) {
      this.isFirstShow = true
      this.init()
      this.resize()
      this.mascot?.show(isReduceMotion)
      this.shield?.show(isReduceMotion)

      if (this.common.startCopyAnimation) {
        this.common.startCopyAnimation()
      }
    }
  }

  setStartCopyAnimation(startCopyAnimation: () => void): void {
    this.common.startCopyAnimation = startCopyAnimation
  }

  load(): void {
    this.isLoaded = true
  }

  init(): void {
    this.common.initRenderer()
    this.common.resize()
    this.mascot?.init()
    this.shield?.init()
  }

  resize(): void {
    this.common.resize()
  }

  scroll(): void {
    this.common.scroll()
  }

  resetMouse(): void {
    this.mascot?.resetLookat()
  }

  update({isReducedMotion}: {isReducedMotion: boolean}): void {
    this.common.update()
    this.mouse.update()
    this.mascot?.update(this.mouse.pos.target, this.mouse.pos.current, isReducedMotion)
    this.common.renderer?.setRenderTarget(null)
    this.common.renderer?.render(this.common.scene, this.common.camera)
  }
}

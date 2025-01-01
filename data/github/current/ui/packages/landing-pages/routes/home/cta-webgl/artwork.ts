import {MathUtils} from 'three'
import Common from './common'
import type Assets from './assets'
import MainScene from './main-scene'
import Background from './background'

export default class Artwork {
  private $wrapper: HTMLElement
  private $canvas: HTMLCanvasElement
  private mainScene?: MainScene
  private background?: Background
  private isInitAnimation: boolean = false
  private isLoaded: boolean = false
  private assets: Assets
  private common: Common = new Common()
  private isReducedMotion: boolean = false
  constructor($wrapper: HTMLElement, $canvas: HTMLCanvasElement, isReducedMotion: boolean, assets: Assets) {
    this.assets = assets
    this.isReducedMotion = isReducedMotion
    this.$wrapper = $wrapper
    this.$canvas = $canvas
    this.init()
  }

  init(): void {
    this.common.init({
      $wrapper: this.$wrapper,
      $canvas: this.$canvas,
    })
    this.background = new Background()
    this.common.scene.add(this.background.group)

    this.mainScene = new MainScene(this.assets, this.common)
    this.common.scene.position.set(0.2, 0.0, 0.0)
    this.common.camera.position.set(0, 2, 3)
    this.common.camera.lookAt(this.common.scene.position)

    this.common.scene.add(this.mainScene.group)
  }

  afterLoad(): void {
    this.mainScene?.init()
    this.isLoaded = true
  }

  resize(): void {
    this.common.resize()
  }

  scroll(isReducedMotion: boolean): void {
    const rectData = this.common.$wrapper?.getBoundingClientRect()
    if (rectData) {
      const s = window.innerHeight
      const e = -rectData.height // window.innerHeight * 0.5 - rectData.height * 0.5;
      const p = Math.min(1.0, Math.max(0.0, MathUtils.mapLinear(rectData.top, s, e, 0.0, 1.0)))
      const initTrigger = rectData.bottom - rectData.height * 0.3 - s < 0
      if (initTrigger && !this.isInitAnimation && this.isLoaded) {
        this.isInitAnimation = true
        if (!this.isReducedMotion) {
          this.mainScene?.initAnimation()
          this.background?.initAnimation()
        }
      }

      this.mainScene?.scroll(isReducedMotion ? 0.5 : p)
    }
  }

  update(isReducedMotion: boolean): void {
    if (isReducedMotion) {
      this.mainScene?.showStatic()
      this.background?.showStatic()
    }
    this.common.update()
    this.mainScene?.update()
    this.common.renderer?.setRenderTarget(null)
    this.common.renderer?.render(this.common.scene, this.common.camera)
  }
}

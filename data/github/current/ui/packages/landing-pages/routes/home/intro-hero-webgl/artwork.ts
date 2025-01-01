import MainScene from './main-scene'
import Background from './background'
import type Assets from '../webgl-utils/assets'
import type Common from './common'
import {MathUtils} from 'three'

export default class Artwork {
  private $wrapper: HTMLElement
  private $canvas: HTMLCanvasElement
  private mainScene?: MainScene
  private background: Background
  private assets: Assets
  private common: Common
  private isCtaHover: boolean = false
  private isCtaAnimation: boolean = false
  private ctaAnimationProgress: number = 0
  private ctaAnimTime: number = 0
  public mascotProgress: {current: number; target: number} = {
    current: 0,
    target: 0,
  }
  public copyProgress: {current: number; target: number} = {
    current: 0,
    target: 0,
  }
  public isRendering: boolean = true

  constructor($wrapper: HTMLElement, $canvas: HTMLCanvasElement, common: Common, assets: Assets) {
    this.$wrapper = $wrapper
    this.$canvas = $canvas
    this.common = common
    this.assets = assets

    this.background = new Background(this.common, this.assets)
    this.common.scene.add(this.background.outputPlane)
    this.mainScene = new MainScene(this.common, this.assets, this.background.fbo, this.background.fbo_blue)

    this.common.camera.position.set(0, 0.0, 2.2)
    this.common.camera.lookAt(this.common.scene.position)

    this.common.scene.add(this.mainScene.group)
  }

  init(): void {
    this.common.init({
      $wrapper: this.$wrapper,
      $canvas: this.$canvas,
    })
    this.background?.init()
    this.mainScene?.init()
    this.resize()
  }

  resize(): void {
    this.common.resize()
    this.background?.resize()

    if (!this.isRendering && this.common.isFinishedIntroAnim && this.copyProgress.target !== 1) {
      this.render()
    }
  }

  scroll(): void {
    const scale = (this.common.cameraTop * 2) / this.common.screenSize.y
    const scrollValue = window.scrollY * scale

    const mascotProgress = MathUtils.smoothstep(scrollValue, 0, 1.0)
    const copyProgress = MathUtils.smoothstep(scrollValue, 0.6, 3)

    this.mascotProgress.target = mascotProgress
    this.copyProgress.target = copyProgress
  }

  updateProgress(progress: {current: number; target: number}, easeScale: number) {
    if (progress.current === progress.target) {
      return
    }
    progress.current += (progress.target - progress.current) * easeScale
    if (Math.abs(progress.current - progress.target) < 0.001) {
      progress.current = progress.target
    }
  }

  render(): void {
    this.background?.update({
      ctaAnimTime: this.ctaAnimTime,
      ctaAnimationProgress: this.ctaAnimationProgress,
    })
    this.mainScene?.update({
      ctaAnimTime: this.ctaAnimTime,
    })

    this.common.renderer?.setRenderTarget(null)
    this.common.renderer?.render(this.common.scene, this.common.camera)
  }

  startCtaAnim(): void {
    this.isCtaHover = true
    this.isCtaAnimation = true
  }

  stopCtaAnim(): void {
    this.isCtaHover = false
  }

  renderOnce(): void {
    this.mascotProgress.target = this.mascotProgress.current = 0
    this.copyProgress.target = this.copyProgress.current = 0
    this.render()
  }

  update(): void {
    this.common.update()
    const easeScale = this.common.getEase(3)
    this.updateProgress(this.mascotProgress, easeScale)
    this.updateProgress(this.copyProgress, easeScale)

    if (this.isCtaHover) {
      this.ctaAnimationProgress += (1 - this.ctaAnimationProgress) * easeScale
    } else {
      this.ctaAnimationProgress += (0 - this.ctaAnimationProgress) * easeScale
    }

    if (this.ctaAnimationProgress < 0.001 && !this.isCtaHover && this.isCtaAnimation) {
      this.ctaAnimationProgress = 0
      this.isCtaAnimation = false
    }

    this.ctaAnimTime += this.ctaAnimationProgress * this.common.delta

    if (this.isRendering || !this.common.isFinishedIntroAnim || this.isCtaAnimation) {
      this.render()
    }

    if (this.mascotProgress.current === 0 && this.copyProgress.current === 0) {
      this.isRendering = false
    }
  }
}

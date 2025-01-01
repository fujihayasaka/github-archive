import {Vector2, Scene, WebGL1Renderer, OrthographicCamera, Clock, LinearEncoding} from 'three'
export default class Common {
  $wrapper?: HTMLElement
  $canvas?: HTMLCanvasElement
  screenSize: Vector2 = new Vector2()
  screenSize_old: Vector2 = new Vector2()
  wrapperOffset: Vector2 = new Vector2()
  aspect: number = 1
  isMobile: boolean = false
  pixelRatio: number = 1
  camera: OrthographicCamera = new OrthographicCamera(-1, 1, 1, -1, 0.01, 200)
  scene: Scene = new Scene()
  fbo_screenSize: Vector2 = new Vector2()
  cameraTop: number = 1.7
  time: number = 0
  delta: number = 0
  declare $mascot: HTMLElement
  mascotAreaOffset: Vector2 = new Vector2()
  renderer?: WebGL1Renderer
  clock?: Clock
  isReducedMotion: boolean = false
  declare startCopyAnimation: () => void

  init({$wrapper, $canvas, $mascot}: {$wrapper: HTMLElement; $canvas: HTMLCanvasElement; $mascot: HTMLElement}): void {
    this.pixelRatio = Math.min(1.5, window.devicePixelRatio)

    this.$canvas = $canvas
    this.$wrapper = $wrapper
    this.$mascot = $mascot

    this.clock = new Clock()
    this.clock.start()
  }

  initRenderer() {
    this.renderer = new WebGL1Renderer({
      antialias: true,
      alpha: true,
      canvas: this.$canvas,
    })
    this.renderer.outputEncoding = LinearEncoding

    this.renderer.setClearColor(0x000000, 0.0)
    this.renderer.setPixelRatio(this.pixelRatio)
  }

  resize(): void {
    const width = this.$wrapper?.clientWidth || 0
    const height = this.$wrapper?.clientHeight || 0

    this.screenSize_old.copy(this.screenSize)
    this.screenSize.set(width, height)

    this.fbo_screenSize.set(width * this.pixelRatio, height * this.pixelRatio)

    this.aspect = width / height

    this.camera.left = -this.cameraTop * this.aspect
    this.camera.right = this.cameraTop * this.aspect
    this.camera.top = this.cameraTop
    this.camera.bottom = -this.camera.top

    this.camera.updateProjectionMatrix()

    this.renderer?.setSize(this.screenSize.x, this.screenSize.y)
  }

  scroll() {
    if (this.$wrapper && this.$mascot) {
      const wrapperRect = this.$wrapper.getBoundingClientRect()
      const mascotRect = this.$mascot.getBoundingClientRect()

      this.mascotAreaOffset.set(
        mascotRect.left - wrapperRect.left + mascotRect.width / 2 - wrapperRect.width / 2,
        -(mascotRect.top - wrapperRect.top + mascotRect.height / 2 - wrapperRect.height / 2) -
          (this.screenSize.y - wrapperRect.height) * 0.5,
      )

      this.wrapperOffset.set(wrapperRect.left, wrapperRect.top)
    }
  }

  getEase(scale: number) {
    return Math.min(1.0, scale * this.delta)
  }

  update(): void {
    const delta = this.clock?.getDelta()
    if (delta) this.delta = delta
    this.time += this.delta
  }
}

import {Vector2, Scene, WebGL1Renderer, OrthographicCamera, Clock, LinearEncoding} from 'three'
export default class Common {
  $wrapper?: HTMLElement
  $canvas?: HTMLElement
  screenSize: Vector2 = new Vector2()
  screenSize_old: Vector2 = new Vector2()
  aspect: number = 1
  isMobile: boolean = false
  pixelRatio: number = 1
  camera: OrthographicCamera = new OrthographicCamera(-1, 1, 1, -1, 0.01, 200)
  scene: Scene = new Scene()
  fbo_screenSize: Vector2 = new Vector2()
  cameraTop: number = 2.3
  time: number = 0
  delta: number = 0
  windowW: number = 0
  windowH: number = 0
  isFinishedIntroAnim: boolean = false
  startCopyAnimation?: () => void

  renderer?: WebGL1Renderer
  clock?: Clock
  isReduceMotion: boolean
  constructor({isReduceMotion}: {isReduceMotion: boolean}) {
    this.isReduceMotion = isReduceMotion
  }

  init({$wrapper, $canvas}: {$wrapper: HTMLElement; $canvas: HTMLCanvasElement}): void {
    this.pixelRatio = Math.min(1.5, window.devicePixelRatio)

    this.renderer = new WebGL1Renderer({
      antialias: true,
      alpha: true,
      canvas: $canvas,
    })
    this.renderer.outputEncoding = LinearEncoding

    this.$canvas = this.renderer.domElement
    $wrapper.appendChild(this.$canvas)
    this.$wrapper = $wrapper

    this.renderer.setClearColor(0xffffff, 0.0)
    this.renderer.setPixelRatio(this.pixelRatio)

    this.clock = new Clock()
    this.clock.start()
    this.resize()
  }

  resize(): void {
    const width = Math.min(1000, this.$wrapper?.clientWidth || 0)
    const height = this.$wrapper?.clientHeight || 0
    this.windowW = window.innerWidth
    this.windowH = window.innerHeight

    this.screenSize_old.copy(this.screenSize)
    this.screenSize.set(width, height)

    this.fbo_screenSize.set(width * this.pixelRatio, height * this.pixelRatio)

    this.aspect = width / height

    this.camera.left = -this.cameraTop * this.aspect
    this.camera.right = this.cameraTop * this.aspect
    this.camera.top = this.cameraTop
    this.camera.bottom = -this.cameraTop

    this.isMobile = this.windowW <= 767

    this.camera.updateProjectionMatrix()

    this.renderer?.setSize(this.screenSize.x, this.screenSize.y)
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

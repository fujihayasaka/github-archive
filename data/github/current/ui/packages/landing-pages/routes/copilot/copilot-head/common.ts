import {
  ACESFilmicToneMapping,
  Clock,
  //  ColorManagement,
  PerspectiveCamera,
  Scene,
  sRGBEncoding,
  Vector2,
  WebGLRenderer,
} from 'three'

class Common {
  sizes: Vector2
  pixelRatio: number
  aspect: number
  scene: Scene
  camera: PerspectiveCamera
  wrapperOffset: Vector2
  delta: number
  time: number
  clock: Clock
  canvasWrapper: HTMLElement
  renderer: WebGLRenderer
  constructor() {
    this.sizes = new Vector2()
    this.pixelRatio = 1
    this.aspect = 1

    this.scene = new Scene()
    this.camera = new PerspectiveCamera(45, this.aspect, 0.1, 200)

    this.camera.position.set(0, 0, 11)
    this.scene.add(this.camera)
    this.wrapperOffset = new Vector2()
    //ColorManagement.enabled = true
    this.delta = 0
    this.time = 0
  }

  init(canvasWrapper: HTMLElement, canvas: HTMLCanvasElement) {
    this.clock = new Clock()
    this.canvasWrapper = canvasWrapper
    this.pixelRatio = Math.min(window.devicePixelRatio, 2)

    this.renderer = new WebGLRenderer({
      canvas,
      antialias: true,
      alpha: true,
    })

    this.renderer.setPixelRatio(this.pixelRatio)
    this.renderer.outputEncoding = sRGBEncoding
    this.renderer.toneMapping = ACESFilmicToneMapping
    this.renderer.toneMappingExposure = 1.5
    this.renderer.setClearColor(0xffffff, 0.0)

    this.resize()
  }

  resize() {
    const wrapperRect = this.canvasWrapper.getBoundingClientRect()
    const width = wrapperRect.width
    const height = wrapperRect.height

    this.aspect = width / height
    this.sizes.set(width, height)

    this.wrapperOffset.set(wrapperRect.left, wrapperRect.top)

    this.camera.aspect = this.aspect
    this.camera.updateProjectionMatrix()

    this.renderer.setSize(width, height)
  }

  getEase(scale: number) {
    return Math.min(1.0, this.delta * scale)
  }

  update() {
    const delta = this.clock.getDelta()
    this.delta = delta
    this.time += this.delta
  }
}

const common = new Common()
export default common

import {Vector2, PerspectiveCamera, Scene, Color, WebGL1Renderer, Clock, LinearEncoding} from 'three'
import type {OrbitControls} from 'three/examples/jsm/controls/OrbitControls'
export default class Common {
  $wrapper?: HTMLElement
  $canvas?: HTMLElement
  screenSize: Vector2 = new Vector2()
  screenSize_old: Vector2 = new Vector2()
  aspect: number = 1
  isMobile: boolean = false
  pixelRatio: number = 1
  // camera: OrthographicCamera = new OrthographicCamera(-1, 1, 1, -1, 0.01, 200)
  camera: PerspectiveCamera = new PerspectiveCamera(30, 1, 0.01, 50)
  scene: Scene = new Scene()
  fbo_screenSize: Vector2 = new Vector2()
  // cameraRight: number = 2
  time: number = 0
  delta: number = 0
  bgColor: Color = new Color(0x0d1117)

  renderer?: WebGL1Renderer
  clock?: Clock
  controls?: OrbitControls

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
    this.scene.add(this.camera)

    // this.controls = new OrbitControls(this.camera, document.body);

    this.renderer.setClearColor(this.bgColor, 1.0)
    this.renderer.setPixelRatio(this.pixelRatio)

    this.clock = new Clock()
    this.clock.start()
    this.resize()
  }

  resize(): void {
    const width = this.$wrapper?.clientWidth || 0
    const height = this.$wrapper?.clientHeight || 0

    this.screenSize_old.copy(this.screenSize)
    this.screenSize.set(width, height)

    this.fbo_screenSize.set(width * this.pixelRatio, height * this.pixelRatio)

    this.aspect = width / height

    // this.camera.left = -this.cameraRight;
    // this.camera.right = this.cameraRight;
    // this.camera.top = this.cameraRight / this.aspect;
    // this.camera.bottom = -this.camera.top;

    this.camera.aspect = this.aspect

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

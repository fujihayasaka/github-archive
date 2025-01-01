import {
  Vector2,
  Vector4,
  Mesh,
  Scene,
  OrthographicCamera,
  WebGLRenderTarget,
  PlaneGeometry,
  ShaderMaterial,
  Color,
  InstancedBufferGeometry,
  InstancedBufferAttribute,
  MathUtils,
  CustomBlending,
  OneFactor,
  OneMinusSrcAlphaFactor,
  AddEquation,
} from 'three'

import background_vert from './shaders/screen-vert'
import background_frag from './shaders/background-frag'

import star_vert from './shaders/star-vert'
import star_frag from './shaders/star-frag'

import bgOutput_frag from './shaders/bgOutput-frag'

import utilsShaders from './shaders/utils-glsl'

import Timeline from './utils/timeline'
import type Assets from '../webgl-utils/assets'
import type Common from './common'

interface CommonUniforms {
  uTime: {value: number}
  uIsFullWidth: {value: number}
  uCtaAnimTime: {value: number}
  uCtaProgress: {value: number}
}

export default class Background {
  fbo_blue: WebGLRenderTarget = new WebGLRenderTarget(10, 10)
  fbo_blueRatio: number = 0.1
  blueFboResolution: Vector2 = new Vector2(10, 10)
  fbo: WebGLRenderTarget = new WebGLRenderTarget(10, 10)
  outputPlane: Mesh = new Mesh()
  bluePlane: Mesh = new Mesh()
  scene: Scene = new Scene()
  camera: OrthographicCamera = new OrthographicCamera(-1, 1, 1, -1, 0.01, 200)
  uProgressBackground: Vector4 = new Vector4(0, 0, 0, 0)
  uProgressStar: Vector4 = new Vector4(0, 0, 0, 0)
  commonUniforms: CommonUniforms = {
    uTime: {value: 0},
    uCtaAnimTime: {
      value: 0,
    },
    uCtaProgress: {
      value: 0,
    },
    uIsFullWidth: {
      value: 0,
    },
  }
  common: Common
  assets: Assets
  constructor(common: Common, assets: Assets) {
    this.common = common
    this.assets = assets
    this.createOutputPlane()
  }

  init() {
    // background scene
    this.bluePlane = new Mesh(
      new PlaneGeometry(2, 2),
      new ShaderMaterial({
        vertexShader: background_vert,
        fragmentShader: utilsShaders + background_frag,
        uniforms: {
          uColor1: {value: new Color(0x0e0aa2)},
          uColor2: {value: new Color(0x9a7cff)},
          uResolution: {value: this.blueFboResolution},
          ...this.commonUniforms,
          uProgress: {
            value: this.uProgressBackground,
          },
        },
        depthTest: false,
        depthWrite: false,
        transparent: true,
        blending: CustomBlending,
        blendEquation: AddEquation,
        blendSrc: OneFactor,
        blendDst: OneMinusSrcAlphaFactor,
      }),
    )

    this.createStars()

    this.camera.position.set(0, 0, 10)

    if (this.common.isReduceMotion) {
      this.uProgressStar.x = 1
      this.uProgressStar.y = 1
      this.uProgressBackground.x = 1
      this.uProgressBackground.y = 1
      this.uProgressBackground.z = 1
    } else {
      const tl = new Timeline()

      tl.to([this.uProgressStar], 1000, {x: 1, easing: 'easeOutCubic'}, 100).to(
        [this.uProgressStar],
        10000,
        {y: 1, easing: 'easeOutExpo'},
        0,
      )

      tl.to([this.uProgressBackground], 1000, {x: 1, easing: 'easeOutCubic'}, 0)
        .to([this.uProgressBackground], 3000, {y: 1, easing: 'easeOutCubic'}, 300)
        .to(
          [this.uProgressBackground],
          5000,
          {
            z: 1,
            easing: 'easeOutCubic',
            onComplete: () => {
              this.common.isFinishedIntroAnim = true
            },
          },
          0,
        )
      tl.start()
    }

    this.resize()
  }

  createStars() {
    const num = 100
    const _geometry = new PlaneGeometry(0.05, 0.05)
    const instancedGeometry = new InstancedBufferGeometry()

    if (_geometry.attributes.position) {
      const vertice = _geometry.attributes.position.clone()
      instancedGeometry.setAttribute('position', vertice)
    }

    if (_geometry.attributes.normal) {
      const normal = _geometry.attributes.normal.clone()
      instancedGeometry.setAttribute('normals', normal)
    }

    if (_geometry.attributes.uv) {
      const uv = _geometry.attributes.uv.clone()
      instancedGeometry.setAttribute('uv', uv)
    }

    const indices = _geometry.index ? _geometry.index.clone() : null
    instancedGeometry.setIndex(indices)

    instancedGeometry.instanceCount = num

    const translates = new InstancedBufferAttribute(new Float32Array(num * 3), 3, false, 1)
    const randoms = new InstancedBufferAttribute(new Float32Array(num * 3), 3, false, 1)
    instancedGeometry.setAttribute('atranslate', translates)
    instancedGeometry.setAttribute('arandom', randoms)

    for (let i = 0; i < 50; i++) {
      const angle = MathUtils.lerp(Math.PI * 0.25, Math.PI * 0.75, Math.random())

      translates.setXYZ(i, angle, Math.random(), 0)
      randoms.setXYZ(i, Math.random(), Math.random(), Math.random())
    }

    const material = new ShaderMaterial({
      vertexShader: star_vert,
      fragmentShader: star_frag,
      uniforms: {
        uMask: {
          value: this.assets.images.star ? this.assets.images.star.texture : null,
        },
        uRadius: {
          value: 2.3,
        },
        uOffsetY: {
          value: 2.2,
        },
        uProgress: {
          value: this.uProgressStar,
        },
        ...this.commonUniforms,
      },
      transparent: true,
      depthTest: false,
      depthWrite: false,
    })

    const mesh = new Mesh(instancedGeometry, material)

    mesh.frustumCulled = false
    this.scene.add(mesh)
  }

  createOutputPlane() {
    this.outputPlane = new Mesh(
      new PlaneGeometry(2, 2),
      new ShaderMaterial({
        vertexShader: background_vert,
        fragmentShader: bgOutput_frag,
        uniforms: {
          uDiffuse_star: {
            value: this.fbo.texture,
          },
          uDiffuse_blue: {
            value: this.fbo_blue.texture,
          },
        },
        depthTest: false,
        depthWrite: false,
        transparent: true,
      }),
    )
  }

  resize() {
    this.fbo.setSize(this.common.fbo_screenSize.x, this.common.fbo_screenSize.y)

    this.blueFboResolution.set(
      Math.round(this.common.fbo_screenSize.x * this.fbo_blueRatio),
      Math.round(this.common.fbo_screenSize.y * this.fbo_blueRatio),
    )

    this.fbo_blue.setSize(this.blueFboResolution.x, this.blueFboResolution.y)

    this.camera.left = -this.common.cameraTop * this.common.aspect
    this.camera.right = this.common.cameraTop * this.common.aspect
    this.camera.top = this.common.cameraTop
    this.camera.bottom = -this.common.cameraTop
    this.camera.updateProjectionMatrix()
  }

  update({ctaAnimTime, ctaAnimationProgress}: {ctaAnimTime: number; ctaAnimationProgress: number}) {
    this.commonUniforms.uTime.value += this.common.delta
    this.commonUniforms.uCtaAnimTime.value = ctaAnimTime
    this.commonUniforms.uCtaProgress.value = ctaAnimationProgress
    this.common.renderer?.setRenderTarget(this.fbo_blue)
    this.common.renderer?.render(this.bluePlane, this.camera)
    this.common.renderer?.setRenderTarget(this.fbo)
    this.common.renderer?.render(this.scene, this.camera)
    this.commonUniforms.uIsFullWidth.value = this.common.screenSize.x <= 1246 ? 1 : 0
  }
}

import {Group, Vector4, Mesh, PlaneGeometry, ShaderMaterial, Color} from 'three'
import vertexShader from './shaders/background-vert'
import fragmentShader from './shaders/background-frag'
import utilsGlsl from './shaders/utils-glsl'

import Timeline from './utils/timeline'

export default class Background {
  group: Group = new Group()
  initTl: Timeline = new Timeline({delay: 0})
  progress: Vector4 = new Vector4(0, 0, 0, 0)
  constructor() {
    this.init()
  }
  init() {
    const plane = new Mesh(
      new PlaneGeometry(2, 1),
      new ShaderMaterial({
        vertexShader,
        fragmentShader: utilsGlsl + fragmentShader,
        uniforms: {
          uColor: {
            value: new Color(0x674ef1),
          },
          uProgress: {
            value: this.progress,
          },
        },
        depthTest: false,
        depthWrite: false,
        transparent: true,
      }),
    )
    plane.renderOrder = 0

    this.group.add(plane)
  }

  showStatic() {
    this.initTl.setProgress(1)
  }

  initAnimation() {
    this.initTl
      .to(
        [this.progress],
        3000,
        {
          x: 1,
          easing: 'easeOutExpo',
        },
        500,
      )
      .to(
        [this.progress],
        500,
        {
          y: 1,
        },
        500,
      )
      .to(
        [this.progress],
        4000,
        {
          z: 1,
          easing: 'easeOutExpo',
        },
        500,
      )
      .start()
  }
}

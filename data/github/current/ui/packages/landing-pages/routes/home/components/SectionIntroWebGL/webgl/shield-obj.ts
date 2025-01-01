import {Group, Mesh, ShaderMaterial, PlaneGeometry, Color, Vector3} from 'three'
import type {Gltf, Image} from './params/assets-type'
import type Common from './common'

import vertexShader from './shaders/obj-vert'
import fragmentShader from './shaders/shield-frag'
import utilsGlsl from './shaders/utils-glsl'
import Timeline from './utils/timeline'

import blurVert from './shaders/blur-vert'
import blurFrag from './shaders/blur-frag'
import type Assets from '../../../webgl-utils/assets'

export default class ShieldObj {
  name: string = 'shield'
  common: Common
  group: Group = new Group()
  group2: Group = new Group()
  gltfs: {[key: string]: Gltf}
  images: {[key: string]: Image}
  progress: Vector3 = new Vector3(0, 0, 0)
  blurMesh: Mesh
  constructor(common: Common, assets: Assets) {
    this.common = common
    this.gltfs = assets.gltfs
    this.images = assets.images
    this.group.add(this.group2)
  }
  init(): void {
    const blur = this.images['shield_blur'] ? this.images['shield_blur'].texture : null
    this.blurMesh = new Mesh(
      new PlaneGeometry(0.47, 0.47),
      new ShaderMaterial({
        vertexShader: blurVert,
        fragmentShader: blurFrag,
        uniforms: {
          uAlpha: {
            value: blur,
          },
          uColor1: {
            value: new Color(0x1010fe),
          },
          uColor2: {
            value: new Color(0x91dfdf),
          },
          uProgress: {
            value: this.progress,
          },
        },
        transparent: true,
      }),
    )

    this.blurMesh.position.set(0, -0.01, -4)
    this.group2.add(this.blurMesh)

    const gltf = this.gltfs[this.name]
    if (gltf && gltf.scene) {
      gltf.scene.traverse(child => {
        if (child instanceof Mesh) {
          const geometry = child.geometry
          const matcapTex = this.images['matcap_mascot'] ? this.images['matcap_mascot'].texture : null
          const ao = this.images['shield_sss'] ? this.images['shield_sss'].texture : null
          const diffuse = this.images['shield_diffuse'] ? this.images['shield_diffuse'].texture : null
          const uniforms = {
            uMatcapTex: {value: matcapTex},
            uAo: {value: ao},
            uDiffuse: {value: diffuse},
          }

          const material = new ShaderMaterial({
            vertexShader,
            fragmentShader: utilsGlsl + fragmentShader,
            uniforms,
            transparent: true,
          })

          const mesh = new Mesh(geometry, material)
          mesh.scale.set(2.5, 2.5, 2.5)
          this.group2.add(mesh)
        }
      })
    }
  }

  show(isReducedMotion: boolean): void {
    if (isReducedMotion) {
      if (this.blurMesh) this.blurMesh.visible = false
    } else {
      this.group2.scale.set(0, 0, 0)
      const tl = new Timeline()
      tl.to([this.group2.scale], 400, {x: 1, y: 1, z: 1, easing: 'easeOutCubic'}, 0)
        .to([this.progress], 4000, {x: 5, easing: 'easeOutCubic'}, 0)
        .to([this.progress], 1000, {y: 1, easing: 'easeOutCubic'}, 3000)
        .to([this.progress], 4000, {z: 1, easing: 'easeOutCubic'}, 3500)
        .start()
    }
  }
}

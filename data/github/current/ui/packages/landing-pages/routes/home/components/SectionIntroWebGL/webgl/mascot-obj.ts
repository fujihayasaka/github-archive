import {Group, Mesh, Vector2, ShaderMaterial, Vector3, MathUtils} from 'three'
import type {MeshStandardMaterial} from 'three'
import type {Gltf, Image, TextureData} from './params/assets-type'
import type Common from './common'

import vertexShader from './shaders/obj-vert'
import fragmentShader from './shaders/obj-frag'
import utilsGlsl from './shaders/utils-glsl'
import Timeline from './utils/timeline'
import type Assets from '../../../webgl-utils/assets'

interface CommonUniforms {
  uResolution: {value: Vector2} // Adjust the type of `value` as needed
}

export default class MascotObj {
  name: string
  common: Common
  group: Group = new Group()
  group2: Group = new Group()
  gltfs: {[key: string]: Gltf}
  images: {[key: string]: Image}
  mascotData: {[key: string]: TextureData}
  commonUniforms: CommonUniforms = {
    uResolution: {value: new Vector2()},
  }
  lookatTarget: Vector3 = new Vector3(0, 0, 0)
  mouseIntensity: {target: number; current: number} = {target: 0, current: 0}
  constructor(name: string, common: Common, assets: Assets, mascotData: {[key: string]: TextureData}) {
    this.group.add(this.group2)
    this.name = name
    this.common = common
    this.gltfs = assets.gltfs
    this.images = assets.images
    this.mascotData = mascotData
    this.commonUniforms.uResolution.value = this.common.fbo_screenSize
  }

  init(): void {
    const gltf = this.gltfs[this.name]
    const group = new Group()
    this.group2.add(group)
    if (gltf && gltf.scene) {
      gltf.scene.traverse(child => {
        if (child instanceof Mesh) {
          this.createNewMesh(child, group)
        }
      })
    }
  }

  createNewMesh(child: Mesh, group: Group): void {
    const geometry = child.geometry
    const _material = child.material as MeshStandardMaterial
    const texData = this.mascotData[child.name as keyof typeof this.mascotData]
    if (!texData) return
    const ao_name = texData.ao
    const color_name = texData.color
    const colorVec = texData.colorVec ? texData.colorVec : _material.color
    const matcap = texData.matcap

    const ao = ao_name && this.images[ao_name] ? this.images[ao_name].texture : null
    const colorTex = color_name && this.images[color_name] ? this.images[color_name].texture : null

    const matcapTex = matcap && this.images[matcap] ? this.images[matcap].texture : null

    const uniforms = {
      uAo: {value: ao},
      uColor: {value: colorVec},
      uColorTex: {value: colorTex},
      uMatcapTex: {value: matcapTex},
      uTranslate: {value: child.position},
      uLightPos: {value: new Vector3(-1, 1, 3)},
      ...this.commonUniforms,
    }

    let mascotType = -1

    switch (this.name) {
      case 'cat':
        mascotType = 0
        break
      case 'copilot':
        mascotType = 1
        group.position.y = -0.05
        break
      case 'duck':
        mascotType = 2
        group.scale.set(1.4, 1.4, 1.4)
        break
    }

    const material = new ShaderMaterial({
      vertexShader,
      fragmentShader: utilsGlsl + fragmentShader,
      uniforms,
      transparent: true,
      defines: {
        USE_COLORTEX: !!colorTex,
        MASCOT_TYPE: mascotType,
      },
    })

    const mesh = new Mesh(geometry, material)
    mesh.position.copy(child.position)
    // mesh.position.y -= 0.05
    group.add(mesh)
  }

  resetLookat() {
    this.lookatTarget.set(0, 0, 1)
    this.group.lookAt(this.lookatTarget)
  }

  show(isReducedMotion: boolean): void {
    if (!isReducedMotion) {
      this.group2.scale.set(0, 0, 0)
      const tl = new Timeline()
      tl.to([this.group2.scale], 600, {x: 1, y: 1, z: 1, easing: 'easeOutCubic'}, 0).start()
    }
  }

  update(mousePosTarget: Vector2, mousePosCurrent: Vector2, isReducedMotion: boolean): void {
    const mouseLength = mousePosTarget.length()
    this.mouseIntensity.target = MathUtils.smootherstep(2.0, 1.0, mouseLength)
    this.mouseIntensity.current += (this.mouseIntensity.target - this.mouseIntensity.current) * this.common.getEase(3.0)

    if (isReducedMotion) {
      this.lookatTarget.set(0, 0, 1).add(this.group.position)
      this.group.lookAt(this.lookatTarget)
    } else {
      this.lookatTarget
        .set(mousePosCurrent.x * 0.3, mousePosCurrent.y * 0.3, 1)
        .multiplyScalar(this.mouseIntensity.current)
        .add(this.group.position)
      this.group.lookAt(this.lookatTarget)
    }
  }
}

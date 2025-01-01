import type {WebGLRenderTarget, MeshStandardMaterial, Texture, Vector2, Color} from 'three'
import {
  Group,
  Vector3,
  Vector4,
  Mesh,
  ShaderMaterial,
  AddEquation,
  CustomBlending,
  ZeroFactor,
  SrcAlphaFactor,
} from 'three'

import cat_data from './params/cat'
import duck_data from './params/duck'
import copilot_data from './params/copilot'

import vertexShader from './shaders/obj-vert'
import fragmentShader from './shaders/obj-frag'
import utilsGlsl from './shaders/utils-glsl'

import Timeline from './utils/timeline'
import type Assets from '../webgl-utils/assets'
import type Common from './common'
import type {MascotData} from './params/mascot-type'

interface MascotCommonUniforms {
  uResolution: {value: Vector2}
  uLightColor1: {value: Color}
  uLightColor2: {value: Color}
  uLightPos: {value: Vector3}
  uLightPos2: {value: Vector3}
  uProgress: {value: Vector3}
  uDiffuse_star: {value: Texture}
  uDiffuse_blue: {value: Texture}
}

interface CommonUniforms {
  uTime: {value: number}
}

export default class MainScene {
  group: Group = new Group()
  bgFbo: WebGLRenderTarget
  bgFbo_blue: WebGLRenderTarget
  groups: Group[] = []
  // _scrollProgress: Vector3 = new Vector3(0, 0, 0)
  // scrollProgress: Vector3 = new Vector3(0, 0, 0)
  commonUniforms: CommonUniforms = {
    uTime: {value: 0},
  }
  common: Common
  assets: Assets
  constructor(common: Common, assets: Assets, bgFbo: WebGLRenderTarget, bgFbo_blue: WebGLRenderTarget) {
    this.common = common
    this.assets = assets
    this.bgFbo = bgFbo
    this.bgFbo_blue = bgFbo_blue
    this.group.position.set(0, 0, 0)
  }

  init(): void {
    const tl = new Timeline({delay: 0})
    if (this.assets.gltfs.cat && this.assets.gltfs.cat.scene) {
      const {group4, group5, mascotCommonUniforms} = this.createNewGroup(this.assets.gltfs.cat.scene, cat_data, 'cat')
      group5.userData.offsetFloatingY = 0.33 * Math.PI * 2
      group4.userData.startPos.set(cat_data.group_data.position.x, -2, 0)

      group4.rotation.set(0, Math.PI * 1.5, 1)

      if (this.common.isReduceMotion) {
        group4.rotation.set(0, 0, 0)
        group4.scale.set(1, 1, 1)
        group4.userData.introPositionProgress.x = 1
        // group4.position.copy(cat_data.group_data.position)
        mascotCommonUniforms.uProgress.value.x = 1
      } else {
        tl.to(
          [group4.rotation],
          3000,
          {
            y: 0,
            z: 0,
            easing: 'easeOutExpo',
          },
          0,
        )
          .to(
            [group4.scale],
            300,
            {
              x: 1,
              y: 1,
              z: 1,
              easing: 'easeOutExpo',
            },
            0,
          )
          .to(
            [group4.userData.introPositionProgress],
            4000,
            {
              x: 1,
              easing: 'easeOutExpo',
            },
            0,
          )
          .to(
            [mascotCommonUniforms.uProgress.value],
            500,
            {
              x: 1,
            },
            0,
          )
      }
    }

    if (this.assets.gltfs.copilot && this.assets.gltfs.copilot.scene) {
      const {group4, group5, mascotCommonUniforms} = this.createNewGroup(
        this.assets.gltfs.copilot.scene,
        copilot_data,
        'copilot',
      )
      group4.userData.startPos.set(-1, -2.5, 0)
      group5.userData.offsetFloatingY = 0.66 * Math.PI * 2

      group4.rotation.set(0, -Math.PI * 1.5, -1)

      if (this.common.isReduceMotion) {
        group4.rotation.y = 0
        group4.rotation.z = 0
        group4.scale.set(1, 1, 1)
        group4.userData.introPositionProgress.x = 1
        // group4.position.copy(copilot_data.group_data.position)
        mascotCommonUniforms.uProgress.value.x = 1
      } else {
        const delay = 600
        tl.to(
          [group4.rotation],
          2400,
          {
            y: 0,
            z: 0,
            easing: 'easeOutExpo',
          },
          delay,
        )
          .to(
            [group4.scale],
            300,
            {
              x: 1,
              y: 1,
              z: 1,
              easing: 'easeOutExpo',
            },
            delay,
          )
          .to(
            [group4.userData.introPositionProgress],
            4400,
            {
              x: 1,
              easing: 'easeOutExpo',
            },
            delay,
          )
          .to(
            [mascotCommonUniforms.uProgress.value],
            500,
            {
              x: 1,
            },
            delay,
          )
      }
    }

    if (this.assets.gltfs.duck && this.assets.gltfs.duck.scene) {
      const {group4, group5, mascotCommonUniforms} = this.createNewGroup(
        this.assets.gltfs.duck.scene,
        duck_data,
        'duck',
      )
      group4.userData.startPos.set(1, -2.5, 0)
      group5.userData.offsetFloatingY = 0

      group4.rotation.set(0, Math.PI * 1.5, -1)

      if (this.common.isReduceMotion) {
        group4.rotation.y = 0
        group4.rotation.z = 0
        group4.scale.set(1, 1, 1)
        group4.userData.introPositionProgress.x = 1
        // group4.position.copy(duck_data.group_data.position)
        mascotCommonUniforms.uProgress.value.x = 1
        if (this.common.startCopyAnimation) {
          this.common.startCopyAnimation()
        }
      } else {
        const delay = 1000
        tl.to(
          [group4.rotation],
          2000,
          {
            y: 0,
            z: 0,
            easing: 'easeOutExpo',
          },
          delay,
        )
          .to(
            [group4.scale],
            300,
            {
              x: 1,
              y: 1,
              z: 1,
              easing: 'easeOutExpo',
            },
            delay,
          )
          .to(
            [group4.userData.introPositionProgress],
            3000,
            {
              x: 1,
              easing: 'easeOutExpo',
            },
            delay,
          )
          .to(
            [mascotCommonUniforms.uProgress.value],
            500,
            {
              x: 1,
              onComplete: () => {
                if (this.common.startCopyAnimation) {
                  this.common.startCopyAnimation()
                }
              },
            },
            delay,
          )

        tl.start()
      }
    }
  }

  createNewGroup(_group: Group, mascot_data: MascotData, name: string) {
    const group5 = new Group()

    group5.userData.position = new Vector3()
    group5.userData.rotation = new Vector3()
    group5.userData.scale = new Vector3(1, 1, 1)
    group5.userData.scrollDistY = -1

    group5.name = 'group5'

    this.groups.push(group5)
    this.group.add(group5)

    const group4 = new Group()
    group4.scale.set(0, 0, 0)
    group4.position.copy(mascot_data.group_data.position)
    group4.userData.startPos = new Vector3()
    group4.userData.desktopPos = new Vector3().copy(mascot_data.group_data.position)
    group4.userData.tabletPos = new Vector3().copy(mascot_data.group_data.tablet_position)
    group4.userData.introPositionProgress = new Vector3(0, 0, 0)
    group4.name = 'group4'
    group5.add(group4)

    const group3 = new Group()

    group3.scale.copy(mascot_data.group_data.scale)
    group3.rotation.copy(mascot_data.group_data.rotation)
    group3.rotation.order = mascot_data.group_data.order
    group3.userData.random = new Vector4(Math.random(), Math.random(), Math.random(), Math.random())
    group4.add(group3)
    group3.name = 'group3'

    const group2 = new Group()
    group2.name = 'group2'
    group3.add(group2)

    const mascotCommonUniforms: MascotCommonUniforms = {
      uResolution: {value: this.common.fbo_screenSize},
      uLightColor1: {value: mascot_data.light_data.color1},
      uLightColor2: {value: mascot_data.light_data.color2},
      uLightPos: {value: mascot_data.light_data.position},
      uLightPos2: {value: mascot_data.light_data.position2},
      uProgress: {value: new Vector3(0, 0, 0)},
      uDiffuse_star: {
        value: this.bgFbo.texture,
      },
      uDiffuse_blue: {
        value: this.bgFbo_blue.texture,
      },
    }

    _group.traverse(child => {
      if (child instanceof Mesh) {
        this.createNewMesh(child, group2, mascot_data, name, mascotCommonUniforms)
      }
    })

    return {group4, group5, mascotCommonUniforms}
  }

  createNewMesh(
    child: Mesh,
    group: Group,
    mascot_data: MascotData,
    name: string,
    mascotCommonUniforms: MascotCommonUniforms,
  ) {
    const geometry = child.geometry
    const _material = child.material as MeshStandardMaterial

    const texData = mascot_data.textures[child.name as keyof typeof mascot_data.textures]

    if (!texData) return

    const ao_name = texData.ao
    const color_name = texData.color
    const colorVec = texData.colorVec ? texData.colorVec : _material.color
    const matcap = texData.matcap

    const ao = ao_name && this.assets.images[ao_name] ? this.assets.images[ao_name].texture : null
    const colorTex = color_name && this.assets.images[color_name] ? this.assets.images[color_name].texture : null

    const matcapTex = matcap && this.assets.images[matcap] ? this.assets.images[matcap].texture : null

    const uniforms = {
      uAo: {value: ao},
      uColor: {value: colorVec},
      uColorTex: {value: colorTex},
      uMatcapTex: {value: matcapTex},
      uTranslate: {value: child.position},
      uViewDir: {
        value: this.common.camera.position,
      },
      ...mascotCommonUniforms,
      ...this.commonUniforms,
    }

    const material = new ShaderMaterial({
      vertexShader,
      fragmentShader: utilsGlsl + fragmentShader,
      uniforms,
      transparent: true,
      defines: {
        USE_COLORTEX: !!colorTex,
        MASCOT_TYPE: name === 'cat' ? 0 : name === 'copilot' ? 1 : 2,
      },
    })

    if (name === 'cat') {
      material.blending = CustomBlending
      material.blendSrc = SrcAlphaFactor
      material.blendDst = ZeroFactor
      material.blendEquation = AddEquation
    }

    const mesh = new Mesh(geometry, material)
    mesh.position.copy(child.position)
    mesh.frustumCulled = false
    group.add(mesh)
  }

  scroll(): void {}

  update({ctaAnimTime}: {ctaAnimTime: number}): void {
    this.commonUniforms.uTime.value += this.common.delta

    for (let i = 0; i < this.groups.length; i++) {
      const group5 = this.groups[i]
      if (!group5) return
      const group4 = group5.getObjectByName('group4') as Group

      let targetPos: Vector3 = group4.userData.desktopPos
      if (this.common.windowW >= 768 && this.common.windowW <= 1011) {
        targetPos = group4.userData.tabletPos
      }

      const group2 = group4.getObjectByName('group2') as Group
      group5.position.y = Math.sin(ctaAnimTime + group5.userData.offsetFloatingY) * 0.05
      group2.rotation.y = Math.sin(ctaAnimTime + group5.userData.offsetFloatingY) * 0.05
      group5.visible = !this.common.isMobile && this.common.windowH >= 640
      group4.position.lerpVectors(group4.userData.startPos, targetPos, group4.userData.introPositionProgress.x)
    }
  }
}

import type Common from './common'
import type Assets from './assets'
import type {MeshStandardMaterial, Vector2, Texture} from 'three'
import {Color, Group, Vector3, MathUtils, Vector4, Mesh, ShaderMaterial} from 'three'
import type {MascotData} from './params/mascot-type'
import cat_data from './params/cat'
import duck_data from './params/duck'
import copilot_data from './params/copilot'

import vertexShader from './shaders/obj-vert'
import fragmentShader from './shaders/obj-frag'
import fragmentShaderBlack from './shaders/blackObj-frag'
import utilsGlsl from './shaders/utils-glsl'

import Timeline from './utils/timeline'

interface CommonUniforms {
  u_time: {value: number}
  uBgColor: {value: Color}
}

interface MascotCommonUniforms {
  u_resolution: {value: Vector2}
  u_lightPos: {value: Vector3}
  uDiffuse_bg: {value: Texture | undefined | null}
  uScrollProgress: {value: number}
  uCameraPos: {value: Vector3}
  uProgress: {value: Vector4}
}

export default class MainScene {
  group: Group = new Group()
  groups: Group[] = []
  commonUniforms: CommonUniforms = {
    u_time: {value: 0},
    uBgColor: {
      value: new Color(0x000000),
    },
  }
  scrollTl: Timeline = new Timeline({delay: 0})
  initTl: Timeline = new Timeline({delay: 0})
  constructor(
    private assets: Assets,
    private common: Common,
  ) {
    this.group.visible = false
    this.group.position.set(0, 0, 0)
    this.commonUniforms.uBgColor.value.copy(this.common.bgColor)
  }

  init(): void {
    const cameraData = {
      target: new Vector3(0, 0, 0),
      position: this.common.camera.position.clone(),
      progress: new Vector3(),
    }

    this.scrollTl.to(
      [cameraData.progress],
      1500,
      {
        x: 1,
        easing: 'easeOutExpo',
        onUpdate: () => {
          const y = MathUtils.lerp(2, -0.5, cameraData.progress.x)
          this.common.camera.position.y = y
          this.common.camera.lookAt(cameraData.target)
        },
      },
      0,
    )

    this.initTl.to(
      [cameraData.progress],
      2000,
      {
        y: 1,
        easing: 'easeOutExpo',
        onUpdate: () => {
          this.group.visible = true
          const targetRadian = MathUtils.lerp(Math.PI * 0.1, Math.PI * 0.43, cameraData.progress.y)
          const targetRadius = MathUtils.lerp(4, 4, cameraData.progress.y)
          const s = Math.sin(targetRadian)
          const c = Math.cos(targetRadian)
          const x = -s * targetRadius
          const z = +c * targetRadius

          this.common.camera.position.x = x
          this.common.camera.position.z = z

          this.common.camera.lookAt(cameraData.target)
        },
      },
      0,
    )

    if (this.assets.gltfs.cat?.scene) {
      const {group5, mascotCommonUniforms} = this.createNewGroup(this.assets.gltfs.cat.scene, cat_data, 'cat')
      group5.position.y = 0.7
      this.initTl
        .to(
          [mascotCommonUniforms.uProgress.value],
          500,
          {
            x: 1,
          },
          250,
        )
        .to(
          [group5.position],
          1800,
          {
            y: 0,
            easing: 'easeOutExpo',
          },
          250,
        )
    }

    if (this.assets.gltfs.copilot?.scene) {
      const {group5, mascotCommonUniforms} = this.createNewGroup(
        this.assets.gltfs.copilot.scene,
        copilot_data,
        'copilot',
      )
      group5.position.y = 0.7
      this.initTl
        .to(
          [mascotCommonUniforms.uProgress.value],
          500,
          {
            x: 1,
          },
          0,
        )
        .to(
          [group5.position],
          1800,
          {
            y: 0,
            easing: 'easeOutExpo',
          },
          0,
        )
    }

    if (this.assets.gltfs.duck?.scene) {
      const {group5, mascotCommonUniforms} = this.createNewGroup(this.assets.gltfs.duck.scene, duck_data, 'duck')
      group5.position.y = 0.7
      this.initTl
        .to(
          [mascotCommonUniforms.uProgress.value],
          500,
          {
            x: 1,
          },
          500,
        )
        .to(
          [group5.position],
          1800,
          {
            y: 0,
            easing: 'easeOutExpo',
          },
          500,
        )
    }
  }

  initAnimation() {
    this.initTl.start()
  }

  showStatic() {
    this.initTl.setProgress(1)
  }

  scroll(progress: number) {
    this.scrollTl.setProgress(progress)
  }

  createNewGroup(_group: Group, mascot_data: MascotData, name: string) {
    const group5 = new Group()

    group5.userData.position = new Vector3()
    group5.userData.rotation = new Vector3()
    group5.userData.scale = new Vector3(1, 1, 1)
    group5.userData.uScrollProgress = new Vector3(0, 0, 0)

    group5.name = 'group5'

    this.groups.push(group5)
    this.group.add(group5)

    const group4 = new Group()
    group4.position.copy(mascot_data.group_data.position)
    group4.name = 'group4'
    group5.add(group4)
    const group3 = new Group()

    group3.scale.copy(mascot_data.group_data.scale)
    group3.rotation.copy(mascot_data.group_data.rotation)
    group3.rotation.order = mascot_data.group_data.order
    group3.userData.random = new Vector4(Math.random(), Math.random(), Math.random(), Math.random())
    group4.add(group3)
    group3.name = 'group3'

    const mascotCommonUniforms: MascotCommonUniforms = {
      u_resolution: {value: this.common.fbo_screenSize},
      u_lightPos: {value: mascot_data.light_data.position},
      uDiffuse_bg: {
        value: this.assets.images.bg?.texture,
      },
      uScrollProgress: {
        value: group5.userData.uScrollProgress,
      },
      uCameraPos: {
        value: this.common.camera.position,
      },
      uProgress: {
        value: new Vector4(0, 0, 0, 0),
      },
    }

    _group.traverse(child => {
      if (child instanceof Mesh) {
        this.createNewMesh(child, group3, mascot_data, name, mascotCommonUniforms)
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

    const texData = mascot_data.textures[child.name]

    if (!texData) return

    const ao_name = texData.ao
    const color_name = texData.color
    const colorVec = texData.colorVec ? texData.colorVec : _material.color

    const ao = this.assets.images[ao_name]?.texture
    const colorTex = color_name ? this.assets.images[color_name]?.texture : null
    const matcapTex = texData.matcap ? this.assets.images[texData.matcap]?.texture : null

    const uniforms = {
      u_ao: {value: ao},
      u_color: {value: colorVec},
      u_colorTex: {value: colorTex},
      u_matcapTex: {value: matcapTex},
      u_noiseRange: {value: texData.noiseRange},
      u_fogRangeZ: {value: texData.fogRangeZ},
      u_translate: {value: child.position},
      uSpecularFactor: {value: texData.specularFactor},
      ...mascotCommonUniforms,
      ...this.commonUniforms,
    }

    const material = new ShaderMaterial({
      vertexShader,
      fragmentShader: utilsGlsl + (texData.blackObj ? fragmentShaderBlack : fragmentShader),
      uniforms,
      transparent: true,
      defines: {
        USE_COLORTEX: !!colorTex,
        MASCOT_TYPE: name === 'cat' ? 0 : name === 'copilot' ? 1 : 2,
      },
    })

    const mesh = new Mesh(geometry, material)
    mesh.renderOrder = 1
    mesh.position.copy(child.position)
    group.add(mesh)
  }

  update(): void {
    this.commonUniforms.u_time.value += this.common.delta
  }
}

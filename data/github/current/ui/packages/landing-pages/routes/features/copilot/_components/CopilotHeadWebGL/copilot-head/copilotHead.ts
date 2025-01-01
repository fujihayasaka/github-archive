// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import Animations from './animations'
import {Mesh, Group, Raycaster, Vector3, DoubleSide, ShaderMaterial} from 'three'
import vertexShader from './shaders/vert'
import fragmentShader from './shaders/frag'
import mouseMng from './mouseMng'
import common from './common'
import assets from './assets'
import type {Diffuse} from './types'

import {getProgress, lerp} from './utils/math'

export default class CopilotHead {
  group: Group
  orientationGroup: Group
  animationGroup: Group
  goggleGroup: Group
  faceGroup: Group
  eyesMeshes: {left: Mesh | null; right: Mesh | null}
  breathing: {rotation: number; position: number}
  lookatTarget: Vector3
  lookatTarget_default: Vector3
  raycaster: Raycaster
  isRaycastHit: boolean
  mouseIntensity: {target: number; current: number}
  uniforms: {fresnelBias: {value: number}; fresnelScale: {value: number}; fresnelPower: {value: number}}
  declare animations: Animations

  constructor() {
    this.group = new Group()
    this.group.visible = false
    this.group.scale.set(0.01, 0.01, 0.01)

    this.orientationGroup = new Group()
    this.animationGroup = new Group()

    this.group.add(this.orientationGroup)
    this.orientationGroup.add(this.animationGroup)

    this.goggleGroup = new Group()
    this.faceGroup = new Group()
    this.animationGroup.add(this.goggleGroup)
    this.animationGroup.add(this.faceGroup)
    this.eyesMeshes = {
      left: null,
      right: null,
    }

    this.breathing = {
      rotation: 0.0,
      position: 0.0,
    }

    this.goggleGroup.userData.rotateX = {
      orientation: 0,
      anim_rotating: 0,
    }

    this.lookatTarget = new Vector3()

    this.lookatTarget_default = new Vector3(-0.4, -0.2, 1.0)

    this.raycaster = new Raycaster()
    this.isRaycastHit = false
    this.mouseIntensity = {
      target: 0,
      current: 0,
    }

    this.uniforms = {
      fresnelBias: {
        value: 0.0,
      },
      fresnelScale: {
        value: 2.0,
      },
      fresnelPower: {
        value: 1.0,
      },
    }
  }

  init() {
    this.addMeshes()
    this.createAnimations()
  }

  addMeshes() {
    const meshes: Array<{mesh: Mesh; isGoggle?: boolean; isFace?: boolean}> = []
    if (!assets.gltfs.head.scene) return

    for (const [key, diffuse] of Object.entries(assets.diffuses)) {
      if (diffuse.texture) {
        const _mesh = assets.gltfs.head.scene.getObjectByName(key) as Mesh | undefined
        if (_mesh) {
          switch (key) {
            case 'Eyes':
            case 'Ears':
            case 'Goggle':
            case 'Glass': {
              const material_left = this.createMaterial(diffuse, key)
              const material_right = this.createMaterial(diffuse, key)

              const left = new Mesh(_mesh.geometry.clone(), material_left)
              const right = new Mesh(_mesh.geometry.clone(), material_right)

              left.name = `${key}_left`
              right.name = `${key}_right`
              right.geometry.scale(-1, 1, 1)

              if (key === 'Eyes') {
                left.position.copy(_mesh.position)
                right.position.copy(_mesh.position)
                right.position.x *= -1

                this.eyesMeshes.left = left
                this.eyesMeshes.right = right
              }

              meshes.push({
                mesh: left,
                isGoggle: diffuse.isGoggle,
                isFace: diffuse.isFace,
              })
              meshes.push({
                mesh: right,
                isGoggle: diffuse.isGoggle,
                isFace: diffuse.isFace,
              })

              if (diffuse.isGoggle) {
                this.goggleGroup.add(left)
                this.goggleGroup.add(right)
              }
              if (diffuse.isFace) {
                this.faceGroup.add(left)
                this.faceGroup.add(right)
              }
              break
            }
            default: {
              const material = this.createMaterial(diffuse, key)
              const newMesh = new Mesh(_mesh.geometry.clone(), material)
              newMesh.name = key
              meshes.push({
                mesh: newMesh,
                isGoggle: diffuse.isGoggle,
                isFace: diffuse.isFace,
              })

              if (diffuse.isGoggle) this.goggleGroup.add(newMesh)
              if (diffuse.isFace) this.faceGroup.add(newMesh)
              break
            }
          }
        }
      }
    }
  }

  createMaterial(diffuse: Diffuse, key: string) {
    /**
     * Materials
     */

    //Main Matcap Material

    const isEye = key === 'Eyes'
    const isGlass = key === 'Glass'

    const dynamicUniforms = {
      uWink: {
        value: 0,
      },
    }
    const material = new ShaderMaterial({
      vertexShader,
      fragmentShader,
      uniforms: {
        ...this.uniforms,
        map: {
          value: diffuse.texture,
        },
        matcap: {
          value: assets.images.matcap.texture,
        },
        uFresnelIntensity: {
          value: diffuse.fresnelIntensity,
        },
        uIsEye: {
          value: isEye,
        },
        uFresnelColor: {
          value: diffuse.fresnelColor,
        },
        uFresnelPosRange: {
          value: diffuse.fresnelPosRange,
        },
        uSpecularIntensity: {
          value: diffuse.specularIntensity,
        },
        ...dynamicUniforms,
      },
      transparent: true, // Enable alpha blending
      side: DoubleSide,
      defines: {
        GLASS: isGlass ? 1 : 0,
      },
    })

    material.userData.uniforms = dynamicUniforms
    return material
  }

  createAnimations() {
    this.animations = new Animations({
      group: this.group,
      animationGroup: this.animationGroup,
      goggleGroup: this.goggleGroup,
      faceGroup: this.faceGroup,
      eyesMeshes: this.eyesMeshes,
    })

    mouseMng.addMousemoveFunc(this.raycast.bind(this))

    document.body.addEventListener('click', () => {
      if (this.isRaycastHit) {
        this.animations.createClickAnimation()
      }
    })
  }

  raycast() {
    this.raycaster.setFromCamera(mouseMng.pos.target, common.camera)
    const intersects = this.raycaster.intersectObject(this.group)

    if (intersects.length > 0) {
      this.isRaycastHit = true
    } else {
      this.isRaycastHit = false
    }
  }

  update() {
    this.breathing.rotation = Math.sin(common.time * 2) * 0.05
    this.breathing.position = Math.sin((common.time + 0.25) * 2) * 0.08

    const mouseLength = mouseMng.pos.target.length()

    this.mouseIntensity.target = getProgress(3, 1.3, mouseLength)

    this.mouseIntensity.current += (this.mouseIntensity.target - this.mouseIntensity.current) * common.getEase(6)

    this.lookatTarget.set(mouseMng.pos.current.x * 0.5, mouseMng.pos.current.y * 0.5, 1)
    this.lookatTarget.lerp(this.lookatTarget_default, 1 - this.mouseIntensity.current)
    this.lookatTarget.y += this.breathing.rotation
    this.orientationGroup.lookAt(this.lookatTarget)
    this.orientationGroup.position.y = this.breathing.position

    let goggleRotateXProgress = getProgress(0.0, 0.5, mouseMng.pos.current2.y)
    goggleRotateXProgress = lerp(0, goggleRotateXProgress, this.mouseIntensity.current)
    goggleRotateXProgress += (this.breathing.rotation + 1.0) * 1.2
    goggleRotateXProgress = Math.min(goggleRotateXProgress, 1.0)
    this.goggleGroup.userData.rotateX.orientation = lerp(0.1, -0.08, goggleRotateXProgress)

    this.goggleGroup.rotation.x = 0

    for (const key in this.goggleGroup.userData.rotateX) {
      const value = this.goggleGroup.userData.rotateX[key]
      this.goggleGroup.rotation.x += value
    }
  }
}

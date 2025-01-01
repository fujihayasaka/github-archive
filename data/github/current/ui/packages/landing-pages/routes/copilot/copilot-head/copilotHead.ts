import Animations from './animations'
import type {Mesh, Texture} from 'three'
import {Group, MeshMatcapMaterial, Raycaster, Vector3} from 'three'
import vertexShader from './shaders/mesh'
import fragmentShader from './shaders/matcap'
import mouseMng from './mouseMng'
import common from './common'
import assets from './assets'

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
  animations: Animations

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
        value: 0.01,
      },
      fresnelScale: {
        value: 2.0,
      },
      fresnelPower: {
        value: 3.0,
      },
    }
  }

  init() {
    this.addMeshes()
    this.createAnimations()
  }

  addMeshes() {
    const meshes: Array<{object: Mesh; isGoggle?: boolean; isFace?: boolean}> = []
    if (!assets.gltfs.head.scene) return

    assets.gltfs.head.scene.traverse(mesh => {
      const object: Mesh = mesh as Mesh
      if (object.isMesh) {
        let texture
        switch (object.name) {
          case 'Goggle':
          case 'LeftEye':
          case 'RightEye':
          case 'Glass001':
            texture = assets.images.bakedGoggle.texture
            break
          case 'HeadBase':
            texture = assets.images.bakedHead.texture
            break
          case 'Screen':
            texture = assets.images.bakedOther.texture
            break
        }
        const isFresnel = object.name === 'HeadBase'

        const isEye = object.name === 'RightEye' || object.name === 'LeftEye'
        object.material = this.createMaterial(texture, isFresnel, isEye)

        switch (object.name) {
          case 'Goggle':
          case 'Glass001':
            meshes.push({
              object,
              isGoggle: true,
            })
            break
          default:
            meshes.push({
              object,
              isFace: true,
            })
            break
        }

        if (object.name === 'RightEye') {
          this.eyesMeshes.right = object
        } else if (object.name === 'LeftEye') {
          this.eyesMeshes.left = object
        }
      }
    })

    for (const item of meshes) {
      const object = item.object
      if (object.parent) object.parent.remove(object)
      if (item.isGoggle) this.goggleGroup.add(object)
      if (item.isFace) this.faceGroup.add(object)
    }
  }

  createMaterial(bakedTexture: Texture | null | undefined, isFresnel: boolean, isEye: boolean) {
    /**
     * Materials
     */

    //Main Matcap Material
    // bakedMaterial.isMeshMatcapMaterial = true;
    const dynamicUniforms = {
      uWink: {
        value: 0,
      },
    }
    const material = new MeshMatcapMaterial({
      map: bakedTexture,
      matcap: assets.images.matcap.texture,
      transparent: true, // Enable alpha blending
    })

    material.onBeforeCompile = shader => {
      shader.uniforms = {
        ...shader.uniforms,
        ...this.uniforms,
        uFresnelIntensity: {
          value: isFresnel ? 1 : 0,
        },
        uIsEye: {
          value: isEye,
        },
        ...dynamicUniforms,
      }

      shader.vertexShader = vertexShader
      shader.fragmentShader = fragmentShader
    }
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

    this.mouseIntensity.current += (this.mouseIntensity.target - this.mouseIntensity.current) * common.getEase(3)

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

import GlifCat from '../assets/cta-webgl-assets/mascot/cat/cat.glb'
import GlifDuck from '../assets/cta-webgl-assets/mascot/duck/duck.glb'
import GlifCopilot from '../assets/cta-webgl-assets/mascot/copilot/copilot.glb'
import MatcapMascot from '../assets/cta-webgl-assets/matcaps/mascot.jpg'
import MatcapCatEye from '../assets/cta-webgl-assets/matcaps/cat_eye.jpg'
import MatcapMetal from '../assets/cta-webgl-assets/matcaps/metal.jpg'
import TextureCatNoseSSS from '../assets/cta-webgl-assets/mascot/cat/textures/nose_sss.jpg'
import TextureCatHeadSSS from '../assets/cta-webgl-assets/mascot/cat/textures/head_sss.jpg'
import TextureCatFaceSSS from '../assets/cta-webgl-assets/mascot/cat/textures/face_sss.jpg'
import TextureCatEyeSSS from '../assets/cta-webgl-assets/mascot/cat/textures/eyes_sss.jpg'
import TextureCatEyeBallSSS from '../assets/cta-webgl-assets/mascot/cat/textures/eyeballs_sss.jpg'
import TextureCatEyeColor from '../assets/cta-webgl-assets/mascot/cat/textures/eye_color.jpg'
import TextureDuckBodySSS from '../assets/cta-webgl-assets/mascot/duck/textures/body_sss.jpg'
import TextureDuckBeakSSS from '../assets/cta-webgl-assets/mascot/duck/textures/beak_sss.jpg'
import TextureDuckEyesSSS from '../assets/cta-webgl-assets/mascot/duck/textures/eyes_sss.jpg'
import TextureDuckEyeballsSSS from '../assets/cta-webgl-assets/mascot/duck/textures/eyeballs_sss.jpg'
import TextureCopilotEyesSSS from '../assets/cta-webgl-assets/mascot/copilot/textures/eyes_sss.jpg'
import TextureCopilotFaceSSS from '../assets/cta-webgl-assets/mascot/copilot/textures/face_sss.jpg'
import TextureCopilotEarsSSS from '../assets/cta-webgl-assets/mascot/copilot/textures/ears_sss.jpg'
import TextureCopilotGlassesSSS from '../assets/cta-webgl-assets/mascot/copilot/textures/glasses_sss.jpg'
import TextureCopilotGoggleSSS from '../assets/cta-webgl-assets/mascot/copilot/textures/goggle_sss.jpg'
import TextureCopilotHeadSSS from '../assets/cta-webgl-assets/mascot/copilot/textures/head_sss.jpg'
import TextureCopilotNeckSSS from '../assets/cta-webgl-assets/mascot/copilot/textures/neck_sss.jpg'

import {TextureLoader} from 'three'
import type {Texture, Group} from 'three'
import {GLTFLoader} from 'three/examples/jsm/loaders/GLTFLoader'

interface Gltf {
  src: string
  scene?: null | Group
}

interface Image {
  src: string
  texture?: null | Texture
  flipY: boolean
}

export default class Assets {
  isLoaded: boolean = false
  gltfs: {[key: string]: Gltf} = {
    cat: {
      src: GlifCat,
      scene: null,
    },
    duck: {
      src: GlifDuck,
      scene: null,
    },
    copilot: {
      src: GlifCopilot,
      scene: null,
    },
  }

  images: {[key: string]: Image} = {
    // matcap
    matcap_mascot: {
      src: MatcapMascot,
      texture: null,
      flipY: false,
    },
    matcap_cateye: {
      src: MatcapCatEye,
      texture: null,
      flipY: false,
    },
    matcap_metal: {
      src: MatcapMetal,
      texture: null,
      flipY: false,
    },
    // cat
    cat_nose_ao: {
      src: TextureCatNoseSSS,
      texture: null,
      flipY: false,
    },
    cat_head_ao: {
      src: TextureCatHeadSSS,
      texture: null,
      flipY: false,
    },
    cat_face_ao: {
      src: TextureCatFaceSSS,
      texture: null,
      flipY: false,
    },
    cat_eye_ao: {
      src: TextureCatEyeSSS,
      texture: null,
      flipY: false,
    },
    cat_eyeball_ao: {
      src: TextureCatEyeBallSSS,
      texture: null,
      flipY: false,
    },

    cat_eye_color: {
      src: TextureCatEyeColor,
      texture: null,
      flipY: false,
    },

    // duck
    duck_body_ao: {
      src: TextureDuckBodySSS,
      texture: null,
      flipY: false,
    },
    duck_beak_ao: {
      src: TextureDuckBeakSSS,
      texture: null,
      flipY: false,
    },
    duck_eyes_ao: {
      src: TextureDuckEyesSSS,
      texture: null,
      flipY: false,
    },
    duck_eyeballs_ao: {
      src: TextureDuckEyeballsSSS,
      texture: null,
      flipY: false,
    },

    // copilot
    copilot_eyes_ao: {
      src: TextureCopilotEyesSSS,
      texture: null,
      flipY: false,
    },
    copilot_face_ao: {
      src: TextureCopilotFaceSSS,
      texture: null,
      flipY: false,
    },
    copilot_ears_ao: {
      src: TextureCopilotEarsSSS,
      texture: null,
      flipY: false,
    },
    copilot_glasses_ao: {
      src: TextureCopilotGlassesSSS,
      texture: null,
      flipY: false,
    },
    copilot_goggle_ao: {
      src: TextureCopilotGoggleSSS,
      texture: null,
      flipY: false,
    },
    copilot_head_ao: {
      src: TextureCopilotHeadSSS,
      texture: null,
      flipY: false,
    },
    copilot_neck_ao: {
      src: TextureCopilotNeckSSS,
      texture: null,
      flipY: false,
    },
  }

  constructor() {}

  async load(callback: () => void) {
    const allPromisess = [...this.loadImages(), ...this.loadGltfs()]

    try {
      await Promise.all(allPromisess)

      this.isLoaded = true

      // All assets loaded
      if (callback) callback()
    } catch (error) {
      // eslint-disable-next-line no-console
      console.log('Error loading assets', error)
    }
  }

  loadGltfs() {
    const loader = new GLTFLoader()

    const promises = Object.values(this.gltfs).map(
      gltf =>
        new Promise((resolve, reject) => {
          loader.load(
            gltf.src,
            loadedGltf => {
              gltf.scene = loadedGltf.scene
              resolve(loadedGltf.scene)
            },
            undefined,
            error => reject(error),
          )
        }),
    )

    return promises
  }

  loadImages() {
    const loader = new TextureLoader()

    const promises = Object.values(this.images).map(
      image =>
        new Promise((resolve, reject) => {
          loader.load(
            image.src,
            texture => {
              image.texture = texture
              texture.flipY = image.flipY
              resolve(texture)
            },
            undefined,
            error => reject(error),
          )
        }),
    )

    return promises
  }
}

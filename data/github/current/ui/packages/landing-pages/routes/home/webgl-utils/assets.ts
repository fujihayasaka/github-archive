import GlbCat from '../assets/webgl-assets/mascot/cat/cat.glb'
import GlbDuck from '../assets/webgl-assets/mascot/duck/duck.glb'
import GlbCopilot from '../assets/webgl-assets/mascot/copilot/copilot.glb'
import GlbShield from '../assets/webgl-assets/mascot/shield/shield.glb'
import MatcapMascot from '../assets/webgl-assets/matcaps/mascot.jpg'
import MatcapCatEye from '../assets/webgl-assets/matcaps/cat_eye.jpg'
import TextureStar from '../assets/webgl-assets/textures/star.jpg'
import TextureCatHeadSSS from '../assets/webgl-assets/mascot/cat/textures/head_sss.jpg'
import TextureCatEyeSSS from '../assets/webgl-assets/mascot/cat/textures/eye_sss.jpg'
import TextureDuckCatEyeColor from '../assets/webgl-assets/mascot/cat/textures/eye_color.jpg'
import TextureDuckBodySSS from '../assets/webgl-assets/mascot/duck/textures/body_sss.jpg'
import TextureCopilotHeadSSS from '../assets/webgl-assets/mascot/copilot/textures/head_sss.jpg'
import TextureShieldSSS from '../assets/webgl-assets/mascot/shield/textures/shield_sss.jpg'
import TextureShieldDiffuse from '../assets/webgl-assets/mascot/shield/textures/shield_diffuse.jpg'
import TextureShieldBlur from '../assets/webgl-assets/mascot/shield/textures/shield_blur.jpg'

import type {Group, Texture} from 'three'
import {TextureLoader} from 'three'
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
  callbacks: Array<() => void> = []
  gltfs: {[key: string]: Gltf} = {
    cat: {
      src: GlbCat,
      scene: null,
    },
    duck: {
      src: GlbDuck,
      scene: null,
    },
    copilot: {
      src: GlbCopilot,
      scene: null,
    },
    shield: {
      src: GlbShield,
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
    star: {
      src: TextureStar,
      texture: null,
      flipY: false,
    },
    // cat
    cat_head_ao: {
      src: TextureCatHeadSSS,
      texture: null,
      flipY: false,
    },
    cat_eye_ao: {
      src: TextureCatEyeSSS,
      texture: null,
      flipY: false,
    },
    cat_eye_color: {
      src: TextureDuckCatEyeColor,
      texture: null,
      flipY: false,
    },

    // duck
    duck_body_ao: {
      src: TextureDuckBodySSS,
      texture: null,
      flipY: false,
    },

    // copilo
    copilot_head_ao: {
      src: TextureCopilotHeadSSS,
      texture: null,
      flipY: false,
    },
    // shield
    shield_sss: {
      src: TextureShieldSSS,
      texture: null,
      flipY: false,
    },
    shield_diffuse: {
      src: TextureShieldDiffuse,
      texture: null,
      flipY: false,
    },
    shield_blur: {
      src: TextureShieldBlur,
      texture: null,
      flipY: true,
    },
  }
  isLoaded: boolean = false

  constructor() {}

  async load(callback: () => void) {
    const allPromisess = [...this.loadImages(), ...this.loadGltfs()]

    try {
      await Promise.all(allPromisess)
      this.isLoaded = true
      if (callback) callback()
    } catch (error) {
      // eslint-disable-next-line no-console
      console.log('Error loading assets', error)
    }
  }

  executeCallbacks() {
    for (const callback of this.callbacks) {
      callback()
    }
  }

  addCallback(callback: () => void) {
    this.callbacks.push(callback)
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

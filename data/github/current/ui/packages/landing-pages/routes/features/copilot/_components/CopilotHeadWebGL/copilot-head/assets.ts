import {sRGBEncoding, TextureLoader, Color, Vector2} from 'three'
import {GLTFLoader} from 'three/examples/jsm/loaders/GLTFLoader'
import type {Gltfs, Diffuses, Images} from './types'

class Assets {
  images: Images
  gltfs: Gltfs
  diffuses: Diffuses
  constructor() {
    const imagePath = '/images/modules/site/lab/'

    this.diffuses = {
      Ears: {
        src: `${imagePath}copilot/ear.webp`,
        texture: null,
        flipY: false,
        encoding: sRGBEncoding,
        isFace: true,
        isGoggle: false,
        fresnelIntensity: 0.6,
        fresnelColor: new Color(0xa9fbff),
        fresnelPosRange: new Vector2(2.0, -1.0),
        matcapIntensity: 1,
        specularIntensity: 1,
      },
      Eyes: {
        src: `${imagePath}copilot/eyes.webp`,
        texture: null,
        flipY: false,
        encoding: sRGBEncoding,
        isFace: true,
        isGoggle: false,
        fresnelIntensity: 0,
        fresnelColor: new Color(0xbf70ff),
        fresnelPosRange: new Vector2(2.0, -1.0),
        matcapIntensity: 0,
        specularIntensity: 0,
      },
      Glass: {
        src: `${imagePath}copilot/glass.webp`,
        texture: null,
        flipY: false,
        encoding: sRGBEncoding,
        isFace: false,
        isGoggle: true,
        fresnelIntensity: 1,
        fresnelColor: new Color(0x5332b3),
        fresnelPosRange: new Vector2(0.0, 1.0),
        matcapIntensity: 0.5,
        specularIntensity: 0,
      },
      Goggle: {
        src: `${imagePath}copilot/goggle.webp`,
        texture: null,
        flipY: false,
        encoding: sRGBEncoding,
        isFace: false,
        isGoggle: true,
        fresnelIntensity: 0.5,
        fresnelColor: new Color(0x91deff),
        fresnelPosRange: new Vector2(0.0, 1.0),
        matcapIntensity: 2,
        specularIntensity: 0,
      },
      Head: {
        src: `${imagePath}copilot/head.webp`,
        texture: null,
        flipY: false,
        encoding: sRGBEncoding,
        isFace: true,
        isGoggle: false,
        fresnelIntensity: 0.6,
        fresnelColor: new Color(0xa9fbff),
        fresnelPosRange: new Vector2(2.0, -2.0),
        matcapIntensity: 1,
        specularIntensity: 1,
      },
      Screen: {
        src: `${imagePath}copilot/screen.webp`,
        texture: null,
        flipY: false,
        encoding: sRGBEncoding,
        isFace: true,
        isGoggle: false,
        fresnelIntensity: 1,
        fresnelColor: new Color(0x000753),
        fresnelPosRange: new Vector2(2.0, -1.0),
        matcapIntensity: 0,
        specularIntensity: 1,
      },
      Vents: {
        src: `${imagePath}copilot/vento.webp`,
        texture: null,
        flipY: false,
        encoding: sRGBEncoding,
        isFace: true,
        isGoggle: false,
        fresnelIntensity: 0,
        fresnelColor: new Color(0xbf70ff),
        fresnelPosRange: new Vector2(2.0, -1.0),
        matcapIntensity: 1,
        specularIntensity: 1,
      },
    }

    this.images = {
      matcap: {
        src: `${imagePath}matcap.png`,
        texture: null,
        flipY: true,
      },
    } as unknown as Images

    this.gltfs = {
      head: {
        src: `${imagePath}copilot/copilot_head.glb`,
        scene: null,
      },
    }
  }

  load(callback: {(): void; (): void}) {
    const allPromisess = [...this.loadImages(), ...this.loadGltfs(), ...this.loadDiffuses()]

    Promise.all(allPromisess)
      // eslint-disable-next-line github/no-then
      .then(() => {
        // All assets loaded
        if (callback) callback()
      })
    /*.catch(error => {
      //console.log('An error occurred', error)
    })*/
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
              if (image.encoding) texture.encoding = image.encoding
              resolve(texture)
            },
            undefined,
            error => reject(error),
          )
        }),
    )

    return promises
  }

  loadDiffuses() {
    const loader = new TextureLoader()

    const promises = Object.values(this.diffuses).map(
      diffuse =>
        new Promise((resolve, reject) => {
          loader.load(
            diffuse.src,
            texture => {
              diffuse.texture = texture
              texture.flipY = diffuse.flipY
              if (diffuse.encoding) texture.encoding = diffuse.encoding
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

const assets = new Assets()
export default assets

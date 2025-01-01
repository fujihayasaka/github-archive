import type {Scene} from 'three'
import {sRGBEncoding, TextureLoader} from 'three'
import {GLTFLoader} from 'three/examples/jsm/loaders/GLTFLoader'

interface Image {
  src: string
  texture: null
  flipY: boolean
  encoding?: number
}

interface Images {
  bakedGoggle: Image
  bakedGoogles: Image
  bakedHead: Image
  bakedOther: Image
  matcap: Image
}

interface gltf {
  src: string
  scene: Scene | null
}

interface gltfs {
  head: gltf
}

class Assets {
  images: Images
  gltfs: gltfs
  constructor() {
    const imagePath = '/images/modules/site/lab/'

    this.images = {
      bakedGoggle: {
        src: `${imagePath}bakedGoggle.png`,
        texture: null,
        flipY: false,
        encoding: sRGBEncoding,
      },
      bakedHead: {
        src: `${imagePath}bakedHead.png`,
        texture: null,
        flipY: false,
        encoding: sRGBEncoding,
      },
      bakedOther: {
        src: `${imagePath}bakedOther.png`,
        texture: null,
        flipY: false,
        encoding: sRGBEncoding,
      },
      matcap: {
        src: `${imagePath}matcap.png`,
        texture: null,
        flipY: true,
      },
    } as unknown as Images

    this.gltfs = {
      head: {
        src: `${imagePath}copilot.glb`,
        scene: null,
      },
    }
  }

  load(callback: {(): void; (): void}) {
    const allPromisess = [...this.loadImages(), ...this.loadGltfs()]

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
}

const assets = new Assets()
export default assets

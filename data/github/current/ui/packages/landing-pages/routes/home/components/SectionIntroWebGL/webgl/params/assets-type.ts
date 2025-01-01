import type {Group, Texture, Color} from 'three'

export interface Gltf {
  src: string
  scene?: null | Group
}

export interface Image {
  src: string
  texture?: null | Texture
  flipY: boolean
}

export interface TextureData {
  ao: string
  color: string | null
  colorVec: Color
  matcap: string
}

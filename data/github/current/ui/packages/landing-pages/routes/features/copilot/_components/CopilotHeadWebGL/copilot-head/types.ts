import type {Scene, Texture, Color, Vector2} from 'three'

export interface Image {
  src: string
  texture: null
  flipY: boolean
  encoding?: number
}

export interface Diffuse {
  src: string
  texture: Texture | null
  flipY: boolean
  encoding?: number
  isGoggle: boolean
  isFace: boolean
  fresnelIntensity: number
  fresnelColor: Color
  fresnelPosRange: Vector2
  matcapIntensity: number
  specularIntensity: number
}

export interface Diffuses {
  Ears: Diffuse
  Eyes: Diffuse
  Glass: Diffuse
  Goggle: Diffuse
  Head: Diffuse
  Screen: Diffuse
  Vents: Diffuse
}

export interface Images {
  matcap: Image
}

export interface Gltf {
  src: string
  scene: Scene | null
}

export interface Gltfs {
  head: Gltf
}

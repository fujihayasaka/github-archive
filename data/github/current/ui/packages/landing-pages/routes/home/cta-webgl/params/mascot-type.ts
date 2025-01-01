import type {Color, Vector3, Vector2, Euler} from 'three'

export interface LightData {
  position: Vector3
}

export interface GroupData {
  position: Vector3
  scale: Vector3
  rotation: Euler
  order: string
}

export interface TextureData {
  ao: string
  color: string | null
  colorVec: Color
  matcap: string
  noiseRange: Vector2
  fogRangeZ: Vector2
  specularFactor: number
  blackObj: boolean
}

export interface MascotData {
  light_data: LightData
  group_data: GroupData
  textures: Record<string, TextureData>
}

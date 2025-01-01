import type {Color, Vector3, Euler} from 'three'

export interface LightData {
  color1: Color
  color2: Color
  position: Vector3
  position2: Vector3
}

export interface GroupData {
  position: Vector3
  tablet_position: Vector3
  scale: Vector3
  rotation: Euler
  order: string
  mascot: {
    position: Vector3
    scale: Vector3
    rotation: Euler
  }
}

export interface TextureData {
  ao: string
  color: string | null
  colorVec: Color
  matcap: string
}

export interface MascotData {
  light_data: LightData
  group_data: GroupData
  textures: {[key: string]: TextureData}
}

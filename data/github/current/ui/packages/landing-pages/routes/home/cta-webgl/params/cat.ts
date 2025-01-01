import {Vector3, Euler, Color, Vector2} from 'three'
import type {LightData, GroupData, TextureData} from './mascot-type'

const light_data: LightData = {
  position: new Vector3(1, 1, 1.5),
}

const group_data: GroupData = {
  position: new Vector3(0, -0.05, 0.1),
  scale: new Vector3(3, 3, 3),
  rotation: new Euler(0, 0, 0),
  order: 'ZYX',
}

const textures: Record<string, TextureData> = {
  nose: {
    ao: 'cat_nose_ao',
    color: null,
    colorVec: new Color(0x000000),
    matcap: 'matcap_metal',
    noiseRange: new Vector2(-0.03, 0.03),
    fogRangeZ: new Vector2(-1.0, -0.3),
    specularFactor: 0.6,
    blackObj: true,
  },
  eye: {
    ao: 'cat_eye_ao',
    color: null,
    colorVec: new Color(0x000000),
    matcap: 'matcap_metal',
    noiseRange: new Vector2(-0.03, 0.03),
    fogRangeZ: new Vector2(-1.0, -0.3),
    specularFactor: 0.6,
    blackObj: true,
  },
  face: {
    ao: 'cat_face_ao',
    color: null,
    colorVec: new Color(0xff69c8),
    matcap: 'matcap_mascot',
    noiseRange: new Vector2(-0.1, 0.1),
    fogRangeZ: new Vector2(-1.0, -0.5),
    specularFactor: 0.05,
    blackObj: false,
  },
  head: {
    ao: 'cat_head_ao',
    color: null,
    colorVec: new Color(0xf046b2),
    matcap: 'matcap_mascot',
    noiseRange: new Vector2(-0.1, 0.1),
    fogRangeZ: new Vector2(-1.0, -0.5),
    specularFactor: 0.3,
    blackObj: false,
  },
  eyeball: {
    ao: 'cat_eyeball_ao',
    color: null,
    colorVec: new Color(0xffa3dd),
    matcap: 'matcap_mascot',
    noiseRange: new Vector2(-0.03, 0.03),
    fogRangeZ: new Vector2(-1.0, -0.3),
    specularFactor: 0.3,
    blackObj: false,
  },
}

export default {
  light_data,
  group_data,
  textures,
}

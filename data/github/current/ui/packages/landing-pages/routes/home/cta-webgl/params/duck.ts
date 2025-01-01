import {Color, Vector2, Vector3, Euler} from 'three'
import type {LightData, GroupData, TextureData} from './mascot-type'
const light_data: LightData = {
  position: new Vector3(1, 1, 1),
}

const group_data: GroupData = {
  position: new Vector3(0.8, -0.2, 0.6),
  scale: new Vector3(4, 4, 4),
  rotation: new Euler(-0.2, -0.15, 0),
  order: 'XZY',
}

const textures: Record<string, TextureData> = {
  body: {
    ao: 'duck_body_ao',
    color: null,
    colorVec: new Color(0xf6b545),
    matcap: 'matcap_mascot',
    noiseRange: new Vector2(-0.03, 0.03),
    fogRangeZ: new Vector2(-1.0, -0.3),
    specularFactor: 0.2,
    blackObj: false,
  },
  beak: {
    ao: 'duck_beak_ao',
    color: null,
    colorVec: new Color(0xf6b545),
    matcap: 'matcap_mascot',
    noiseRange: new Vector2(-0.03, 0.03),
    fogRangeZ: new Vector2(-1.0, -0.3),
    specularFactor: 0.2,
    blackObj: false,
  },
  eyes: {
    ao: 'duck_eyes_ao',
    color: null,
    colorVec: new Color(0x000000),
    matcap: 'matcap_metal',
    noiseRange: new Vector2(-0.03, 0.03),
    fogRangeZ: new Vector2(-1.0, -0.3),
    specularFactor: 0.6,
    blackObj: true,
  },
  eyeballs: {
    ao: 'duck_eyeballs_ao',
    color: null,
    colorVec: new Color(0x000000),
    matcap: 'matcap_metal',
    noiseRange: new Vector2(-0.03, 0.03),
    fogRangeZ: new Vector2(-1.0, -0.3),
    specularFactor: 0.6,
    blackObj: true,
  },
}

export default {light_data, group_data, textures}

import {Vector3, Euler, Color, Vector2} from 'three'
import type {LightData, GroupData, TextureData} from './mascot-type'

const light_data: LightData = {
  position: new Vector3(1, 1, 1),
}

const group_data: GroupData = {
  position: new Vector3(-0.8, 0, -0.3),
  scale: new Vector3(2.8, 2.8, 2.8),
  rotation: new Euler(-0.1, -0.3, 0),
  order: 'XZY',
}

const bodyColor = new Color(0x6143e6)

const textures: Record<string, TextureData> = {
  eyes: {
    ao: 'copilot_eyes_ao',
    color: null,
    colorVec: new Color(0x1946d4),
    matcap: 'matcap_mascot',
    noiseRange: new Vector2(-0.03, 0.03),
    fogRangeZ: new Vector2(-1.0, -0.3),
    specularFactor: 0.2,
    blackObj: false,
  },
  face: {
    ao: 'copilot_face_ao',
    color: null,
    colorVec: new Color(0x0000a3),
    matcap: 'matcap_mascot',
    noiseRange: new Vector2(-0.03, 0.03),
    fogRangeZ: new Vector2(-1.0, -0.3),
    specularFactor: 0.3,
    blackObj: false,
  },
  glasses: {
    ao: 'copilot_glasses_ao',
    color: null,
    colorVec: new Color(0x1f0a94),
    matcap: 'matcap_mascot',
    noiseRange: new Vector2(-0.03, 0.03),
    fogRangeZ: new Vector2(-1.0, -0.3),
    specularFactor: 0.3,
    blackObj: false,
  },
  goggle: {
    ao: 'copilot_goggle_ao',
    color: null,
    colorVec: bodyColor,
    matcap: 'matcap_mascot',
    noiseRange: new Vector2(-0.03, 0.03),
    fogRangeZ: new Vector2(-1.0, -0.3),
    specularFactor: 0.2,
    blackObj: false,
  },
  head: {
    ao: 'copilot_head_ao',
    color: null,
    colorVec: bodyColor,
    matcap: 'matcap_mascot',
    noiseRange: new Vector2(-0.03, 0.03),
    fogRangeZ: new Vector2(-1.0, -0.3),
    specularFactor: 0.4,
    blackObj: false,
  },
  neck: {
    ao: 'copilot_neck_ao',
    color: null,
    colorVec: bodyColor,
    matcap: 'matcap_mascot',
    noiseRange: new Vector2(-0.03, 0.03),
    fogRangeZ: new Vector2(-1.0, -0.3),
    specularFactor: 0.0,
    blackObj: false,
  },
  ears: {
    ao: 'copilot_ears_ao',
    color: null,
    colorVec: bodyColor,
    matcap: 'matcap_mascot',
    noiseRange: new Vector2(-0.03, 0.03),
    fogRangeZ: new Vector2(-1.0, -0.3),
    specularFactor: 0.4,
    blackObj: false,
  },
}

export default {
  light_data,
  group_data,
  textures,
}

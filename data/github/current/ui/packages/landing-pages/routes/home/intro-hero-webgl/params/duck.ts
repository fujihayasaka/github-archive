import {Color, Vector3, Euler} from 'three'
import type {LightData, GroupData, TextureData} from './mascot-type'

const light_data: LightData = {
  color1: new Color(0xbf7600),
  color2: new Color(0xffebad),
  position: new Vector3(1, 1, 0.4),
  position2: new Vector3(-0.5, -1, 0.6),
}

const group_data: GroupData = {
  position: new Vector3(0.3, -1.2, 0),
  tablet_position: new Vector3(0.1, -0.7, 0),
  scale: new Vector3(1.5, 1.5, 1.5),
  rotation: new Euler(0, -0.9, -0.8),
  order: 'ZYX',
  mascot: {
    position: new Vector3(0, 0, 0),
    scale: new Vector3(1, 1, 1),
    rotation: new Euler(-Math.PI * 0.4, 0, Math.PI * 0.5),
  },
}

const textures: {[key: string]: TextureData} = {
  body: {
    ao: 'duck_body_ao',
    color: null,
    colorVec: new Color(0xf6b545),
    matcap: 'matcap_mascot',
  },
  beak: {
    ao: 'duck_body_ao',
    color: null,
    colorVec: new Color(0xf6b545),
    matcap: 'matcap_mascot',
  },
  eyes: {
    ao: 'duck_body_ao',
    color: null,
    colorVec: new Color(0x000000),
    matcap: 'matcap_mascot',
  },
  eyeballs: {
    ao: 'duck_body_ao',
    color: null,
    colorVec: new Color(0x000000),
    matcap: 'matcap_mascot',
  },
}

export default {
  light_data,
  group_data,
  textures,
}

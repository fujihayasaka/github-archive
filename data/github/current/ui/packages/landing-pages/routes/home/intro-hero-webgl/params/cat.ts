import {Color, Vector3, Euler} from 'three'
import type {LightData, GroupData, TextureData} from './mascot-type'

const light_data: LightData = {
  color1: new Color(0x9514b3),
  color2: new Color(0xbf7600),
  position: new Vector3(-1, 1, 1.0),
  position2: new Vector3(1, -1, 0.4),
}

const group_data: GroupData = {
  position: new Vector3(0.6, -0.6, 2.0),
  tablet_position: new Vector3(0.5, -0.2, 2.0),
  scale: new Vector3(1.1, 1.1, 1.1),
  rotation: new Euler(0, -1.1, -0.6),
  order: 'ZYX',
  mascot: {
    position: new Vector3(0, 0.0, 0.0),
    scale: new Vector3(1, 1, 1),
    rotation: new Euler(-Math.PI * 0.4, 0, Math.PI * 0.5),
  },
}

const textures: {[key: string]: TextureData} = {
  nose: {
    ao: 'cat_head_ao',
    color: null,
    colorVec: new Color(0x000000),
    matcap: 'matcap_mascot',
  },
  eye: {
    ao: 'cat_eye_ao',
    color: 'cat_eye_color',
    colorVec: new Color(0x000000),
    matcap: 'matcap_cateye',
  },
  face: {
    ao: 'cat_head_ao',
    color: null,
    colorVec: new Color(0xff8fd6),
    matcap: 'matcap_mascot',
  },
  head: {
    ao: 'cat_head_ao',
    color: null,
    colorVec: new Color(0xf763c1),
    matcap: 'matcap_mascot',
  },

  eyeball: {
    ao: 'cat_head_ao',
    color: null,
    colorVec: new Color(0xffffff),
    matcap: 'matcap_mascot',
  },
}

export default {
  light_data,
  group_data,
  textures,
}

import {Color, Vector3, Euler} from 'three'
import type {LightData, GroupData, TextureData} from './mascot-type'

const light_data: LightData = {
  color1: new Color(0x7a4ced),
  color2: new Color(0xce5fe8),
  position: new Vector3(-1, 0, 2.0),
  position2: new Vector3(1.0, -1, 1.0),
}

const group_data: GroupData = {
  position: new Vector3(-0.5, -0.8, 0),
  tablet_position: new Vector3(-0.5, -0.3, 0),
  scale: new Vector3(1.3, 1.3, 1.3),
  rotation: new Euler(0, 0.8, 0.8),
  order: 'ZYX',
  mascot: {
    position: new Vector3(0, 0, 0),
    scale: new Vector3(1, 1, 1),
    rotation: new Euler(-Math.PI * 0.4, 0, Math.PI * 0.5),
  },
}

const bodyColor = new Color(0x9e55f8)

const textures: {[key: string]: TextureData} = {
  eyes: {
    ao: 'copilot_head_ao',
    color: null,
    colorVec: new Color(0x3963ef),
    matcap: 'matcap_mascot',
  },
  face: {
    ao: 'copilot_head_ao',
    color: null,
    colorVec: new Color(0x05014d),
    matcap: 'matcap_mascot',
  },
  glass: {
    ao: 'copilot_head_ao',
    color: null,
    colorVec: new Color(0x6325b0),
    matcap: 'matcap_mascot',
  },
  goggle: {
    ao: 'copilot_head_ao',
    color: null,
    colorVec: new Color(0x995be3),
    matcap: 'matcap_mascot',
  },
  head: {
    ao: 'copilot_head_ao',
    color: null,
    colorVec: bodyColor,
    matcap: 'matcap_mascot',
  },
}

export default {
  light_data,
  group_data,
  textures,
}

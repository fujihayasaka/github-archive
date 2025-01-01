import {Color} from 'three'
import type {TextureData} from './assets-type'

const bodyColor = new Color(0x9e55f8)

export const copilotTextureData: {[key: string]: TextureData} = {
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

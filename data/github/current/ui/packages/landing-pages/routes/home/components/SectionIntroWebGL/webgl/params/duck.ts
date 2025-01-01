import {Color} from 'three'
import type {TextureData} from './assets-type'

export const duckTextureData: {[key: string]: TextureData} = {
  body: {
    ao: 'duck_body_ao',
    color: null,
    colorVec: new Color(0xf5ae33),
    matcap: 'matcap_mascot',
  },
  beak: {
    ao: 'duck_body_ao',
    color: null,
    colorVec: new Color(0xf5ae33),
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

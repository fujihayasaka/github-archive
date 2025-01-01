import {Color} from 'three'
import type {TextureData} from './assets-type'

export const catTextureData: {[key: string]: TextureData} = {
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

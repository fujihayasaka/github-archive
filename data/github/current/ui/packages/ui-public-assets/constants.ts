import {join} from 'path'
import {fullPathFromRoot} from '@github-ui/client-build-tools/path-utils'

export const ASSETS_DIR_PATH = fullPathFromRoot('ui/packages/ui-public-assets/assets')
export const POSTCSS_ASSETS_PATH = join(ASSETS_DIR_PATH, 'postcss-assets.txt')
export const FINGERPRINT_MANIFEST_PATH = 'public/assets/manifest.static.json'
export const FINGERPRINT_MAPPING_PATH = join(ASSETS_DIR_PATH, 'fingerprint-map.json')
export const WEBPACK_MANIFEST_PATH = fullPathFromRoot('public/assets/manifest.json')
export const WEBPACK_ASSETS_PATH = join(ASSETS_DIR_PATH, 'webpack-assets.txt')
export const ALL_ASSETS_PATH = join(ASSETS_DIR_PATH, 'all-assets.json')
export const MOVE_ASSETS_PATH = join(ASSETS_DIR_PATH, 'move-assets.json')
export const DUPLICATE_ASSETS_PATH = join(ASSETS_DIR_PATH, 'duplicate-assets.json')

export const IGNORED_PATHS = ['SERVICEOWNERS', 'CODEOWNERS', '**/ui/packages/ui-public-assets/**']
export const ASSET_EXTENSIONS = ['.png', '.jpg', '.jpeg', '.gif', '.glb', '.svg', '.webp', '.mp4']
export const MOVE_EXTENSIONS = ['.js', '.css', '.scss', '.tsx', '.ts']

import {fullPathFromRoot, globFromRoot} from '@github-ui/client-build-tools/path-utils'

export function getAssetsBasePath() {
  return process.env.ASSETS_BASE_PATH || 'public/assets'
}

// Gets all manifest paths (except UI): manifest.relay.json, manifest.static.json, manifest.css.json, manifest.alloy.json, manifest.json
export function getAllManifestsPaths() {
  const assetsBasePath = getAssetsBasePath()
  return [...globFromRoot(`${assetsBasePath}/manifest.*.json`), fullPathFromRoot(`${assetsBasePath}/manifest.json`)]
}

export function getUIManifestPath() {
  return fullPathFromRoot(`${getAssetsBasePath()}/ui-manifest.json`)
}

export function getStaticAssetManifestPath() {
  return fullPathFromRoot(`${getAssetsBasePath()}/manifest.static.json`)
}

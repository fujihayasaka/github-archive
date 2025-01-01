import type {Image} from '../types/image'

export function isLatestCuratedImage(imageName: string): boolean {
  return /Latest( \([\w.]+\))?$/.test(imageName)
}

export function isCanaryCuratedImage(imageName: string): boolean {
  return imageName.endsWith('- Canary')
}

export function curatedImagesSortFn(a: Image, b: Image): number {
  // 1. Latest images should be placed at the begin of list
  // 2. Canary images should be placed at the end of list because they are used in test env only
  // 3. all other images should be sorted by displayName
  return (
    Number(isLatestCuratedImage(b.displayName)) - Number(isLatestCuratedImage(a.displayName)) ||
    Number(isCanaryCuratedImage(a.displayName)) - Number(isCanaryCuratedImage(b.displayName)) ||
    a.displayName.localeCompare(b.displayName)
  )
}

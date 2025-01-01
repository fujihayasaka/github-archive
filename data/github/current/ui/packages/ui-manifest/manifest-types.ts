import type {CSSFeatureFlag, JSFeatureFlag} from '@github-ui/feature-flags/client-feature-flags'
import type {ClientFeatureFlags, ProjectActorFeatureFlags, FeaturePreviews} from '@github-ui/memex-feature-flags'

export interface JSManifest {
  [key: string]: {
    src: string
    files?: string[]
    cssFiles?: string[]
    blocking?: boolean
  }
}

export interface CSSManifest {
  [key: string]: {
    src: string
    files?: string[]
  }
}

export interface AlloyManifest {
  entries: Record<string, string>
  chunks: string[]
  ssrNames: string[]
  manifest: string
}

export interface BundlerFlag {
  flag: string
  bundler: string
}

export interface UIManifestBase {
  gitSha: string
  bundlerFlags: BundlerFlag[]
  featureFlags: {
    js: readonly JSFeatureFlag[]
    css: readonly CSSFeatureFlag[]
    memex: {
      client: readonly ClientFeatureFlags[]
      projectActor: readonly ProjectActorFeatureFlags[]
      previews: readonly FeaturePreviews[]
    }
  }
}
export type UIManifestBaseKey = keyof UIManifestBase

const baseSampleForKeys: UIManifestBase = {
  gitSha: '',
  bundlerFlags: [],
  featureFlags: {
    js: [],
    css: [],
    memex: {
      client: [],
      projectActor: [],
      previews: [],
    },
  },
}
export const baseManifestKeys = new Set(Object.keys(baseSampleForKeys) as UIManifestBaseKey[])

export type UIManifest = UIManifestBase & {
  webpack: JSManifest
  css: CSSManifest
  alloy: AlloyManifest
  vite: JSManifest & CSSManifest
} & Record<string, JSManifest>

export interface StaticAssetManifest {
  [key: string]: string
}

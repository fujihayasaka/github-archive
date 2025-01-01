import bundlerFlagsJson from '@github-ui/client-build-tools/bundler-flags.json' with {type: 'json'}
import type {BundlerFlag} from './manifest-types.ts'

export const bundlerFlags = Object.values(bundlerFlagsJson) as BundlerFlag[]

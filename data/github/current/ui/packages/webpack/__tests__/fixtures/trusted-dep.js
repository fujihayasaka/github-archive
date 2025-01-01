import {incrementTrustedSubDepCache} from './trusted-sub-dep'

let cache = 0

export function incrementTrustedCache() {
  return {
    trusted: cache++,
    trustedSubDepIndirect: incrementTrustedSubDepCache(),
  }
}

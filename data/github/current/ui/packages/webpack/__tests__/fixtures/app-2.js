import {incrementTrustedSubDepCache} from './trusted-sub-dep'
import {incrementCache} from './untrusted-dep'

export default function handleRequest() {
  return {
    trustedSubDepDirect: incrementTrustedSubDepCache(),
    untrusted: incrementCache(),
    name: 'app-2',
  }
}

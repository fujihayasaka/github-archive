import {incrementTrustedCache} from './trusted-dep'
import {incrementCache} from './untrusted-dep'

export default function handleRequest(args) {
  return {
    ...incrementTrustedCache(),
    untrusted: incrementCache(),
    name: 'app-1',
    data: args.data,
  }
}

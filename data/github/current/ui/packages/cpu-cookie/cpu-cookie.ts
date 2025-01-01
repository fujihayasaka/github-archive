import {setCookie} from '@github-ui/cookies'
import {getCPUBucket} from '@github-ui/cpu-bucket'

export function setupCPUCookie() {
  setCookie('cpu_bucket', getCPUBucket())
}

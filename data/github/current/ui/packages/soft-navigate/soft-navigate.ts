import {startSoftNav} from '@github-ui/soft-nav/state'
import {visit} from '@github/turbo'

export const softNavigate: typeof visit = (url, turboOptions) => {
  // visit won't fire a `turbo:click` event, so we need to manually start the soft navigation process.
  startSoftNav('turbo')
  visit(url, {...turboOptions})
}

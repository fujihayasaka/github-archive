import {controller, attr} from '@github/catalyst'
import {waitForConsentPreferences} from '@github-ui/cookie-consent'
import {doNotTrack} from '@github-ui/do-not-track'

import {init} from '@fullstory/browser'

const fsOrgID = 'o-1FH3DA-na1'

@controller
export class FullstoryCaptureElement extends HTMLElement {
  @attr fsScriptDomain = ''

  async connectedCallback() {
    if (doNotTrack()) {
      return
    }

    const consent = await waitForConsentPreferences()
    if (consent?.['Analytics']) {
      const fsScriptUrl = new URL('./fs.js', import.meta.url).toString().split('//')[1]
      init({
        orgId: fsOrgID,
        script: fsScriptUrl,
      })
    }
  }
}

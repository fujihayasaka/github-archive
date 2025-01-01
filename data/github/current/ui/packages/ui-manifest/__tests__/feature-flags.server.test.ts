import {describe, expect, it} from '@github-ui/tests'
import {getClientFeatureFlags} from '../feature-flags'
import {cssFeatureFlags, jsFeatureFlags} from '@github-ui/feature-flags/client-feature-flags'

describe('Feature Flags Manifest', () => {
  it('should return the js and css feature flags', () => {
    const {js, css} = getClientFeatureFlags()

    expect(js).toEqual(jsFeatureFlags)
    expect(css).toEqual(cssFeatureFlags)
  })
})

import {CheckCircleIcon, LinkExternalIcon, SmileyIcon} from '@primer/octicons-react'
import {Blankslate} from '@primer/react/experimental'

export function ReactCoreExamplesFeatureFlagEnabled() {
  return (
    <Blankslate>
      <Blankslate.Visual>
        <CheckCircleIcon size="medium" />
      </Blankslate.Visual>
      <Blankslate.Heading>
        Welcome To A Feature Flag Enabled Page <SmileyIcon />
      </Blankslate.Heading>
      <Blankslate.Description>
        This route is feature flagged and can only be seen when <code>react_core_examples_feature_flag</code> is enabled
      </Blankslate.Description>
      <Blankslate.PrimaryAction href="feature_flag?_features=!react_core_examples_feature_flag">
        Disable feature flag <LinkExternalIcon />
      </Blankslate.PrimaryAction>
    </Blankslate>
  )
}

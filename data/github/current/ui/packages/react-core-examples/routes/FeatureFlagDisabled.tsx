import {LinkExternalIcon, XCircleIcon} from '@primer/octicons-react'
import {Blankslate} from '@primer/react/experimental'

export function ReactCoreExamplesFeatureFlagDisabled() {
  return (
    <Blankslate>
      <Blankslate.Visual>
        <XCircleIcon size="medium" />
      </Blankslate.Visual>
      <Blankslate.Heading>Feature Flag Disabled Page</Blankslate.Heading>
      <Blankslate.Description>
        This route is feature flagged and can only be seen when <code>react_core_examples_feature_flag</code> is
        disabled
      </Blankslate.Description>
      <Blankslate.PrimaryAction href="feature_flag?_features=react_core_examples_feature_flag">
        Enable feature flag <LinkExternalIcon />
      </Blankslate.PrimaryAction>
    </Blankslate>
  )
}

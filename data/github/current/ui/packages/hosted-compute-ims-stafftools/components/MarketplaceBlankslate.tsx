import {Blankslate} from '@primer/react/experimental'
import {Constants} from '../helpers/constants'
import {Urls} from '../helpers/paths'

export function MarketplaceBlankslate() {
  return (
    <Blankslate border>
      <Blankslate.Heading>{Constants.blankslateTitle}</Blankslate.Heading>
      <Blankslate.Description>{Constants.blankslateDescription}</Blankslate.Description>
      <Blankslate.SecondaryAction href={Urls.imsRepoLink}>Learn more about IMS</Blankslate.SecondaryAction>
    </Blankslate>
  )
}

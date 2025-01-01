import {isFeatureEnabled} from '@github-ui/feature-flags'
import Canada from './Canada'
import China from './China'
import Default from './Default'
import SouthKorea from './SouthKorea'
import UnitedStates from './UnitedStates'
import type {GeneralConsentLanguageProps} from './types'

type ConsentLanguageProps = GeneralConsentLanguageProps & {
  country: string
}

function ConsentLanguage({country, children, ...props}: ConsentLanguageProps) {
  const Component = getComponent(country)

  return <Component {...props}>{children}</Component>
}

function getComponent(country: string): React.FC<GeneralConsentLanguageProps> {
  switch (country) {
    case 'CA':
      return Canada
    case 'CN':
      return China
    case 'KR':
      return SouthKorea
    case 'US':
      if (isFeatureEnabled('contact_requests_implicit_opt_in')) {
        return UnitedStates
      } else {
        return Default
      }
    default:
      return Default
  }
}

export default ConsentLanguage

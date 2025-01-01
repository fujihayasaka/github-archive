import Canada from './Canada'
import China from './China'
import Default from './Default'
import SouthKorea from './SouthKorea'
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
    case 'KR':
      return SouthKorea
    case 'CA':
      return Canada
    case 'CN':
      return China
    default:
      return Default
  }
}

export default ConsentLanguage

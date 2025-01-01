import Adobe from './logos/Adobe'
import AmericanAirlines from './logos/AmericanAirlines'
import Amplifon from './logos/Amplifon'
import Bolt from './logos/Bolt'
import CoyoteLogistics from './logos/CoyoteLogistics'
import Coinbase from './logos/Coinbase'
import Datadog from './logos/Datadog'
import Decathlon from './logos/Decathlon'
import DeutcheVermögensberatung from './logos/DeutcheVermögensberatung'
import Doctolib from './logos/Doctolib'
import DowJones from './logos/DowJones'
import Duolingo from './logos/Duolingo'
import Elanco from './logos/Elanco'
import ErnstAndYoung from './logos/ErnstAndYoung'
import Ford from './logos/Ford'
import Fidelity from './logos/Fidelity'
import GeneralMotors from './logos/GeneralMotors'
import Hashicorp from './logos/Hashicorp'
import HomeDepot from './logos/HomeDepot'
import Intel from './logos/Intel'
import Itau from './logos/Itau'
import Kpmg from './logos/Kpmg'
import LinkedIn from './logos/LinkedIn'
import MercadoLibre from './logos/MercadoLibre'
import MercedesBenz from './logos/MercedesBenz'
import OttoGroup from './logos/OttoGroup'
import Plaid from './logos/Plaid'
import Philips from './logos/Philips'
import Postmates from './logos/Postmates'
import ProcterAndGamble from './logos/ProcterAndGamble'
import Shopify from './logos/Shopify'
import SocieteGenerale from './logos/SocieteGenerale'
import Spotify from './logos/Spotify'
import Stripe from './logos/Stripe'
import Telus from './logos/Telus'
import ThreeM from './logos/ThreeM'
import Vodafone from './logos/Vodafone'

/**
 * Render SVG logo as React component.
 *
 * When adding a new logo:
 * - It's safe to remove the fill property because Logo Suite sets that property via CSS.
 * - Logos must have a <title> tag for accessibility.
 * - If an SVG has className such as `st0` or `st1`, namespace the class to avoid conflicts. e.g. from .sg0 to .company-sg0
 * - If a single logo doesn't look aligned compared to the surrounding logos, consider experimenting with margin (directly on the SVG) to align it.
 * - Pro tip: If you're given a figma file, you can right click on the logo and copy the SVG code directly.
 */
export const LogoSuiteMap: {[key: string]: () => JSX.Element} = {
  Adobe,
  '3M': ThreeM,
  'American Airlines': AmericanAirlines,
  Amplifon,
  Bolt,
  'Coyote Logistic': CoyoteLogistics,
  Coinbase,
  Datadog,
  Decathlon,
  'Deutsche Vermögensberatung': DeutcheVermögensberatung,
  Doctolib,
  Duolingo,
  'Dow Jones': DowJones,
  'Ernst and Young': ErnstAndYoung,
  Elanco,
  Ford,
  Fidelity,
  'General Motors': GeneralMotors,
  Hashicorp,
  'Home Depot': HomeDepot,
  Intel,
  Itau,
  KPMG: Kpmg,
  LinkedIn,
  'Mercado Libre': MercadoLibre,
  'Mercedes Benz': MercedesBenz,
  'Otto Group': OttoGroup,
  Plaid,
  Philips,
  Postmates,
  'Procter and Gamble': ProcterAndGamble,
  Shopify,
  'Societe Generale': SocieteGenerale,
  Spotify,
  Stripe,
  Telus,
  Vodafone,
}

export const Logo = ({name}: {name: string}) => {
  const Component = LogoSuiteMap[name]
  if (Component) {
    return <Component />
  }
  return null
}

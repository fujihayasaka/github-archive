import Accenture from './logos/Accenture'
import Adobe from './logos/Adobe'
import AI21 from './logos/AI21'
import AmericanAirlines from './logos/AmericanAirlines'
import Amplifon from './logos/Amplifon'
import ATT from './logos/ATT'
import Bolt from './logos/Bolt'
import CarlsbergGroup from './logos/CarlsbergGroup'
import CocaCola from './logos/CocaCola'
import Cohere from './logos/Cohere'
import Coinbase from './logos/Coinbase'
import CoyoteLogistics from './logos/CoyoteLogistics'
import Datadog from './logos/Datadog'
import Decathlon from './logos/Decathlon'
import DeepSeek from './logos/DeepSeek'
import DeutcheVermögensberatung from './logos/DeutcheVermögensberatung'
import Doctolib from './logos/Doctolib'
import DowJones from './logos/DowJones'
import Duolingo from './logos/Duolingo'
import Elanco from './logos/Elanco'
import ErnstAndYoung from './logos/ErnstAndYoung'
import FedEx from './logos/FedEx'
import Fidelity from './logos/Fidelity'
import Ford from './logos/Ford'
import GeneralMotors from './logos/GeneralMotors'
import Hashicorp from './logos/Hashicorp'
import HM from './logos/HM'
import HomeDepot from './logos/HomeDepot'
import HP from './logos/HP'
import HSBC from './logos/HSBC'
import Infosys from './logos/Infosys'
import Intel from './logos/Intel'
import Itau from './logos/Itau'
import Kpmg from './logos/Kpmg'
import LinkedIn from './logos/LinkedIn'
import MercadoLibre from './logos/MercadoLibre'
import MercedesBenz from './logos/MercedesBenz'
import Meta from './logos/Meta'
import Microsoft from './logos/Microsoft'
import MistralAI from './logos/MistralAI'
import Nasa from './logos/Nasa'
import OpenAI from './logos/OpenAI'
import OttoGroup from './logos/OttoGroup'
import Philips from './logos/Philips'
import Plaid from './logos/Plaid'
import Postmates from './logos/Postmates'
import ProcterAndGamble from './logos/ProcterAndGamble'
import Shopify from './logos/Shopify'
import SocieteGenerale from './logos/SocieteGenerale'
import Spotify from './logos/Spotify'
import Stripe from './logos/Stripe'
import Telus from './logos/Telus'
import ThreeM from './logos/ThreeM'
import Vercel from './logos/Vercel'
import Vodafone from './logos/Vodafone'
import xAI from './logos/XAI'

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
  Accenture,
  '3M': ThreeM,
  Adobe,
  'AI21 Labs': AI21,
  'American Airlines': AmericanAirlines,
  Amplifon,
  'AT&T': ATT,
  Bolt,
  'Carlsberg Group': CarlsbergGroup,
  'Coca-Cola': CocaCola,
  Cohere,
  'Coyote Logistic': CoyoteLogistics,
  Coinbase,
  Datadog,
  Decathlon,
  DeepSeek,
  'Deutsche Vermögensberatung': DeutcheVermögensberatung,
  Doctolib,
  Duolingo,
  'Dow Jones': DowJones,
  'Ernst and Young': ErnstAndYoung,
  Elanco,
  FedEx,
  Ford,
  Fidelity,
  'General Motors': GeneralMotors,
  Hashicorp,
  'Home Depot': HomeDepot,
  HP,
  HSBC,
  'H&M': HM,
  Infosys,
  Intel,
  Itau,
  KPMG: Kpmg,
  LinkedIn,
  'Mercado Libre': MercadoLibre,
  'Mercedes Benz': MercedesBenz,
  Meta,
  Microsoft,
  'Mistral AI': MistralAI,
  Nasa,
  OpenAI,
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
  Vercel,
  Vodafone,
  xAI,
}

export const Logo = ({name}: {name: string}) => {
  const Component = LogoSuiteMap[name]
  if (Component) {
    return <Component />
  }
  return null
}

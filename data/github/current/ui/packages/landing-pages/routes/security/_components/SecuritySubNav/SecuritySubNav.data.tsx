import {ROUTES} from './../../_utils/config'

export const SUBNAV_LINKS = {
  logo: {
    label: 'GitHub Security',
    url: ROUTES.security,
  },
  items: [
    {
      label: 'Advanced Security',
      url: ROUTES.advancedSecurity,
    },
    {
      label: 'Secret Protection',
      url: ROUTES.secretProtection,
    },
    {
      label: 'Code Security',
      url: ROUTES.codeSecurity,
    },
    {
      label: 'Supply Chain',
      url: ROUTES.softwareSupplyChain,
    },
    {
      label: 'Plans and Pricing',
      url: ROUTES.plans,
    },
  ],
} as const

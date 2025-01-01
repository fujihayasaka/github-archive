import imgBento1 from './hero-bento-1.webp'
import imgBento1sm from './hero-bento-1-sm.webp'

import imgBento2 from './hero-bento-2.webp'
import imgBento2sm from './hero-bento-2-sm.webp'

const COPY = {
  label: 'GitHub Advanced Security',
  title: ['Security that moves at the', 'speed of development'],
  cta1: {
    label: 'Request a demo',
    href: '/security/advanced-security/demo?ref_cta=Request%20demo&ref_loc=hero&ref_page=%2Fadvanced_security_lp',
    analytics: {
      marketingAnalyticsEvent: {
        action: 'request_demo',
        tag: 'button',
        context: 'CTAs',
        location: 'hero',
      },
    },
  },
  cta2: {
    label: 'See plans & pricing',
    href: '/security/plans?ref_cta=pricing&ref_loc=hero&ref_page=%2Fadvanced_security_lp',
    analytics: {
      marketingAnalyticsEvent: {
        action: 'see_plans_pricing',
        tag: 'button',
        context: 'CTAs',
        location: 'hero',
      },
    },
  },
  logos: [
    {
      src: '/images/modules/site/enterprise/advanced-security/logos/hashicorp.svg',
      alt: 'HashiCorp',
      height: 42,
    },
    {
      src: '/images/modules/site/enterprise/advanced-security/logos/carlsberg.svg',
      alt: 'Carlsberg Group',
      height: 64,
    },
    {
      src: '/images/modules/site/enterprise/advanced-security/logos/mercado-libre.svg',
      alt: 'Mercado Libre',
      height: 40,
    },
    {
      src: '/images/modules/site/enterprise/advanced-security/logos/3m.svg',
      alt: '3M',
      height: 48,
    },
    {
      src: '/images/modules/site/enterprise/advanced-security/logos/linkedin.svg',
      alt: 'LinkedIn',
      height: 36,
    },
    {
      src: '/images/modules/site/enterprise/advanced-security/logos/otto.svg',
      alt: 'Otto Group',
      height: 32,
    },
    {
      src: '/images/modules/site/enterprise/advanced-security/logos/datadog.svg',
      alt: 'Datadog',
      height: 36,
    },
    {
      src: '/images/modules/site/enterprise/advanced-security/logos/telus.svg',
      alt: 'Telus',
      height: 36,
    },
    {
      src: '/images/modules/site/enterprise/advanced-security/logos/kpmg.svg',
      alt: 'KPMG',
      height: 38,
    },
  ],
  bentos: [
    {
      img: {
        sm: imgBento1sm,
        lg: imgBento1,
      },
      title: ['Stop leaks before', 'they start'],
      link: {
        label: 'Explore Secret Protection',
        href: '/security/advanced-security/secret-protection',
        analytics: {
          marketingAnalyticsEvent: {
            action: 'explore_secret_protection',
            tag: 'link',
            context: 'CTAs',
            location: 'hero',
          },
        },
      },
    },
    {
      img: {
        sm: imgBento2sm,
        lg: imgBento2,
      },
      title: ['Fix vulnerabilities', 'in your code'],
      link: {
        label: 'Explore Code Security',
        href: '/security/advanced-security/code-security',
        analytics: {
          marketingAnalyticsEvent: {
            action: 'explore_code_security',
            tag: 'link',
            context: 'CTAs',
            location: 'hero',
          },
        },
      },
    },
  ],
} as const

export default COPY

const COPY = {
  title: 'Two layers of powerful protection',
  description: 'Combine Secret Protection and Code Security to safeguard your code from every angle.',
  link: {
    label: 'See plans & pricing',
    href: '/security/plans',
    analytics: {
      marketingAnalyticsEvent: {
        action: 'see_plans_pricing',
        tag: 'link',
        context: 'CTAs',
        location: 'river',
      },
    },
  },
  plans: [
    {
      label: 'Add-on',
      title: 'Secret Protection',
      description: 'For teams and organizations serious about stopping secret leaks.',
      price: {
        value: 19,
        currency: 'USD',
        currencySymbol: '$',
        detailText: 'per active committer/month',
      },
      cta1: {
        label: 'Request a demo',
        href: '/security/advanced-security/demo?ref_cta=Request%20demo&ref_loc=body_sp&ref_page=%2Fadvanced_security_lp&utm_campaign=Demo_utmroutercampaign',
        analytics: {
          marketingAnalyticsEvent: {
            action: 'request_demo_secret',
            tag: 'button',
            context: 'CTAs',
            location: 'pricing',
          },
        },
      },
      cta2: {
        label: 'Contact sales',
        href: '/security/contact-sales?ref_cta=Contact+sales&ref_loc=body_sp&ref_page=%2Fadvanced_security_lp',
        analytics: {
          marketingAnalyticsEvent: {
            action: 'contact_sales_secret',
            tag: 'button',
            context: 'CTAs',
            location: 'pricing',
          },
        },
      },
      detailText: 'Team or Enterprise plan required',
    },
    {
      label: 'Add-on',
      title: 'Code Security',
      description: 'For teams and organizations committed to fixing vulnerabilities before production.',
      price: {
        value: 30,
        currency: 'USD',
        currencySymbol: '$',
        detailText: 'per active committer/month',
      },
      cta1: {
        label: 'Request a demo',
        href: '/security/advanced-security/demo?ref_cta=Request%20demo&ref_loc=body_cs&ref_page=%2Fadvanced_security_lp&utm_campaign=Demo_utmroutercampaign',
        analytics: {
          marketingAnalyticsEvent: {
            action: 'request_demo_code',
            tag: 'button',
            context: 'CTAs',
            location: 'pricing',
          },
        },
      },
      cta2: {
        label: 'Contact sales',
        href: '/security/contact-sales?ref_cta=Contact+sales&ref_loc=body_cs&ref_page=%2Fadvanced_security_lp',
        analytics: {
          marketingAnalyticsEvent: {
            action: 'contact_sales_code',
            tag: 'button',
            context: 'CTAs',
            location: 'pricing',
          },
        },
      },
      detailText: 'Team or Enterprise plan required',
    },
  ],
} as const

export default COPY

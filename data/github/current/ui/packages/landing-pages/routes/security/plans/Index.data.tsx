import type {HeroProps} from './components/sections/Hero/Hero'
import type {FeaturesProps} from './components/sections/Features/Features'

const HERO_PLANS_ITEMS: HeroProps['plans'] = [
  {
    label: 'Add-on',
    title: 'GitHub Secret Protection',
    description: 'For teams and organizations serious about stopping secret leaks.',
    price: {
      value: 19,
      currency: 'USD',
      currencySymbol: '$',
      detailText: 'per active committer/month',
    },
    cta1: {
      label: 'Request a demo',
      href: '/security/advanced-security/demo?ref_cta=Request%20demo&ref_loc=hero_sp&ref_page=%2Fsecurity_plans_lp&utm_campaign=Demo_utmroutercampaign',
      analytics: {
        marketingAnalyticsEvent: {
          action: 'request_demo_secret',
          tag: 'button',
          context: 'CTAs',
          location: 'hero',
        },
      },
    },
    cta2: {
      label: 'Contact sales',
      href: '/security/contact-sales?ref_cta=Contact+sales&ref_loc=hero_sp&ref_page=%2Fsecurity_plans_lp',
      analytics: {
        marketingAnalyticsEvent: {
          action: 'contact_sales_secret',
          tag: 'button',
          context: 'CTAs',
          location: 'hero',
        },
      },
    },
    detailText: 'Team or Enterprise plan required',
  },
  {
    label: 'Add-on',
    title: 'GitHub Code Security',
    description: 'For teams and organizations committed to fixing vulnerabilities before production.',
    price: {
      value: 30,
      currency: 'USD',
      currencySymbol: '$',
      detailText: 'per active committer/month',
    },
    cta1: {
      label: 'Request a demo',
      href: '/security/advanced-security/demo?ref_cta=Request%20demo&ref_loc=hero_cs&ref_page=%2Fsecurity_plans_lp&utm_campaign=Demo_utmroutercampaign',
      analytics: {
        marketingAnalyticsEvent: {
          action: 'request_demo_code',
          tag: 'button',
          context: 'CTAs',
          location: 'hero',
        },
      },
    },
    cta2: {
      label: 'Contact sales',
      href: '/security/contact-sales?ref_cta=Contact+sales&ref_loc=hero_cs&ref_page=%2Fsecurity_plans_lp',
      analytics: {
        marketingAnalyticsEvent: {
          action: 'contact_sales_code',
          tag: 'button',
          context: 'CTAs',
          location: 'hero',
        },
      },
    },
    detailText: 'Team or Enterprise plan required',
  },
]

export const PlansTiers = {
  Free: 'Free',
  Team: 'Team',
  Enterprise: 'Enterprise',
} as const

export type PlansTiers = (typeof PlansTiers)[keyof typeof PlansTiers]

// This pattern allows for an easy future injection of the tier names via CMS or any other localisation system
const TIERS_COPY: Record<PlansTiers, string> = {
  [PlansTiers.Free]: 'Free',
  [PlansTiers.Team]: 'Team',
  [PlansTiers.Enterprise]: 'Enterprise',
}
const localizedTierNames = [TIERS_COPY[PlansTiers.Free], TIERS_COPY[PlansTiers.Team], TIERS_COPY[PlansTiers.Enterprise]]

const FEATURES_CATEGORY_ITEMS: Array<Omit<FeaturesProps['categories'][number], 'aria'>> = [
  {
    title: 'GitHub Secret Protection',
    tiers: localizedTierNames,
    features: [
      {
        title: 'Push protection',
        description: 'Prevent secret exposures by proactively blocking secrets before they reach your code.',
        availability: ['Public repositories', true, true],
      },
      {
        title: 'Secret scanning',
        description: 'Detect and manage exposed secrets across git history, pull requests, issues, and wikis.',
        availability: ['Public repositories', true, true],
      },
      {
        title: 'Provider patterns',
        description:
          'GitHub collaborates with AWS, Azure, and Google Cloud to detect secrets with high accuracy. This minimizes false positives, letting you focus on what matters.',
        availability: ['Public repositories', true, true],
      },
      {
        title: 'Provider notification',
        description:
          'Providers get real-time alerts when their tokens appear in public code, enabling them to notify, quarantine, or revoke secrets.',
        availability: ['Public repositories', 'Public repositories', 'Public repositories'],
      },
      {
        title: 'Validity checks',
        description: 'Prioritize active secrets with validity checks for provider patterns.',
        availability: [false, true, true],
      },
      {
        title: 'Copilot secret scanning',
        description: 'Use AI to detect unstructured like passwords—without the noise.',
        availability: [false, true, true],
      },
      {
        title: 'Generic patterns',
        description:
          'Detect tokens from unknown providers, including HTTP authentication headers, connection strings, and private keys.',
        availability: [false, true, true],
      },
      {
        title: 'Custom patterns',
        description: 'Create your own patterns and find organization-specific secrets.',
        availability: [false, true, true],
      },
      {
        title: 'Push protection bypass controls',
        description: 'Manage who can bypass push protection and when.',
        availability: [false, true, true],
      },
      {
        title: 'Insights in security overview',
        description:
          'Understand how risk is distributed across your organization with security metrics and insight dashboards.',
        availability: [false, true, true],
      },
      {
        title: 'Scan history API',
        description: 'Review how and when GitHub scans your repositories for secrets.',
        availability: [false, true, true],
      },
    ],
  },
  {
    title: 'GitHub Code Security',
    tiers: localizedTierNames,
    features: [
      {
        title: 'Copilot Autofix',
        description:
          'Powered by GitHub Copilot, generate automatic fixes for 90% of alert types in JavaScript, Typescript, Java, and Python.',
        availability: ['Public repositories', true, true],
      },
      {
        title: 'Third party extensibility for code scanning alerts',
        description: 'Centralize your findings across all your scanning tools via SARIF upload to GitHub.',
        availability: ['Public repositories', true, true],
      },
      {
        title: 'Contextual vulnerability intelligence and advice',
        description: 'Quickly remediate with context provided by Copilot Autofix.',
        availability: ['Public repositories', true, true],
      },
      {
        title: 'CodeQL',
        description: 'Uncover vulnerabilities in your code with our industry-leading semantic code analysis.',
        availability: ['Public repositories', true, true],
      },
      {
        title: 'Security campaigns',
        description: 'Reduce security debt and burn down your security backlog with security campaigns.',
        availability: [false, true, true],
      },
      {
        title: 'Dependency graph',
        description:
          'Get a clear view of your project’s dependencies with a summary of manifest, lock files, and submitted dependencies via the API.',
        availability: [true, true, true],
      },
      {
        title: 'Dependency review action',
        description:
          'Catch insecure dependencies before adding them and get insights on licenses, dependents, and age.',
        availability: [false, true, true],
      },
      {
        title: 'Dependabot custom auto-triage rules',
        description: 'Define alert-centric policies to control how Dependabot handles alerts and pull requests.',
        availability: [false, true, true],
      },
      {
        title: 'Dependabot security updates with grouped updates',
        description: 'Automated pull requests that batch dependency updates for known vulnerabilities.',
        availability: [true, true, true],
      },
      {
        title: 'Dependabot version updates',
        description: 'Automated pull requests that keep your dependencies up to date.',
        availability: [true, true, true],
      },
      {
        title: 'Insights in security overview',
        description: 'Get a clear view of risk distribution with security metrics and dashboards.',
        availability: [false, true, true],
      },
    ],
  },
]

export const COPY = {
  hero: {
    plans: HERO_PLANS_ITEMS,
  },
  features: {
    categories: FEATURES_CATEGORY_ITEMS,
    aria: {
      included: 'Included',
      notIncluded: 'Not included',
    },
  },
} as const

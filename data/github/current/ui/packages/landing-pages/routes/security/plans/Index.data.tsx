import type {FaqProps} from './components/sections/Faq/Faq'
import type {HeroProps} from './components/sections/Hero/Hero'
import type {FeaturesProps} from './components/sections/Features/Features'

const HERO_PLANS_ITEMS: HeroProps['plans'] = [
  {
    label: 'Add-on',
    title: 'GitHub Secret Protection',
    description: 'For teams and organizations ready to protect against secret leaks.',
    price: {
      value: 19,
      currency: 'USD',
      currencySymbol: '$',
      detailText: 'per active committer/month',
    },
    cta1: {
      label: 'Request a demo',
      // TODO: Update once known
      href: '#',
    },
    cta2: {
      label: 'Contact sales',
      // TODO: Update once known
      href: '#',
    },
    detailText: 'Requires Teams or Enterprise plan',
  },
  {
    label: 'Add-on',
    title: 'GitHub Code Security',
    description: 'For teams and organizations aiming to fix code vulnerabilities before production.',
    price: {
      value: 30,
      currency: 'USD',
      currencySymbol: '$',
      detailText: 'per active committer/month',
    },
    cta1: {
      label: 'Request a demo',
      // TODO: Update once known
      href: '#',
    },
    cta2: {
      label: 'Contact sales',
      // TODO: Update once known
      href: '#',
    },
    detailText: 'Requires Teams or Enterprise plan',
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

const FEATURES_CATEGORY_ITEMS: FeaturesProps['categories'] = [
  {
    title: 'GitHub Secret Protection',
    tiers: localizedTierNames,
    features: [
      {
        title: 'Push protection',
        description:
          'Prevent secret exposures with push protection, which proactively blocks secrets from being pushed into your code.',
        availability: ['Public repositories', true, true],
      },
      {
        title: 'Secret scanning',
        description:
          'Scan your GitHub perimeter for secrets, including git history, pull request content, issues, discussions, and wikis. Manage incidents with secret scanning alerts.',
        availability: ['Public repositories', true, true],
      },
      {
        title: 'Provider patterns',
        description:
          'GitHub works directly with service providers like AWS, Azure, and Google Cloud to build detectors for their specific secret formats. This ensures a low false positive rate and allows you to focus on what matters.',
        availability: ['Public repositories', true, true],
      },
      {
        title: 'Provider notification',
        description:
          'Providers receive real-time notifications when their token formats appear in public code, allowing them to take action like notifying, quarantining or even revoking the secret.',
        availability: ['Public repositories', 'Public repositories', 'Public repositories'],
      },
      {
        title: 'Validity checks',
        description: 'Prioritize active secrets with validity checks for provider patterns.',
        availability: [false, true, true],
      },
      {
        title: 'Copilot secret scanning',
        description: 'Use AI to detect unstructured like passwords, without the noise.',
        availability: [false, true, true],
      },
      {
        title: 'Generic patterns',
        description:
          'Find tokens that are not issued by specific providers, like HTTP authentication headers, connection strings, and private keys.',
        availability: [false, true, true],
      },
      {
        title: 'Custom patterns',
        description: 'Create your own patterns and find organization-specific secrets.',
        availability: [false, true, true],
      },
      {
        title: 'Push protection bypass controls',
        description: 'Manage when push protection can be bypassed, in addition to who can bypass push protection.',
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
          'Powered by Copilot, generate automatic fixes for 90% of alert types in JavaScript, Typescript, Java, and Python.',
        availability: ['Public repositories', true, true],
      },
      {
        title: 'Third party extensibility for code scanning alerts',
        description: 'Centralize your findings across all your scanning tools via SARIF upload to GitHub.',
        availability: ['Public repositories', true, true],
      },
      {
        title: 'Contextual vulnerability intelligence and advice',
        description:
          'Powered by Copilot, feel empowered to take quick remediation action with context provided with Copilot Autofix.',
        availability: ['Public repositories', true, true],
      },
      {
        title: 'CodeQL',
        description: 'Uncover vulnerabilities in your code with our industry-leading semantic code analysis. ',
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
          'Identify and understand your project’s dependencies. The dependency graph is a summary of the manifest and lock files stored in a repository and any dependencies that are submitted for the repository using the dependency submission API.',
        availability: [true, true, true],
      },
      {
        title: 'Dependency Review Action',
        description:
          'Dependency review lets you catch insecure dependencies before you introduce them to your environment, and provides information on license, dependents, and age of dependencies.',
        availability: [false, true, true],
      },
      {
        title: 'Dependabot custom auto-triage rules',
        description:
          'Create and manage your own alert-centric policies to define how Dependabot behaves across alerts and pull requests.',
        availability: [false, true, true],
      },
      {
        title: 'Dependabot security updates with grouped updates',
        description:
          'Dependabot security updates are automated pull requests that help you update dependencies with known vulnerabilities.',
        availability: [true, true, true],
      },
      {
        title: 'Dependabot version updates',
        description:
          'Dependabot version updates are automated pull requests that help you keep your dependencies up-to-date.',
        availability: [true, true, true],
      },
      {
        title: 'Insights in security overview',
        description:
          'Understand how risk is distributed across your organization with security metrics and insight dashboards.',
        availability: [false, true, true],
      },
    ],
  },
]

const FAQ_ITEMS: FaqProps['items'] = [
  {
    title: 'Group 1',
    items: [
      {
        question: 'Question 1',
        answer: ['Answer'],
      },
      {
        question: 'Question 2',
        answer: ['Answer'],
      },
      {
        question: 'Question 3',
        answer: ['Answer'],
      },
    ],
  },
  {
    title: 'Group 2',
    items: [
      {
        question: 'Question 1',
        answer: ['Answer'],
      },
      {
        question: 'Question 2',
        answer: ['Answer'],
      },
      {
        question: 'Question 3',
        answer: ['Answer'],
      },
    ],
  },
  {
    title: 'Group 3',
    items: [
      {
        question: 'Question 1',
        answer: ['Answer'],
      },
      {
        question: 'Question 2',
        answer: ['Answer'],
      },
      {
        question: 'Question 3',
        answer: ['Answer'],
      },
    ],
  },
]

export const COPY = {
  hero: {
    title: 'Enable native security for every repository',
    label: 'Plans and Pricing',
    plans: HERO_PLANS_ITEMS,
  },
  features: {
    categories: FEATURES_CATEGORY_ITEMS,
  },
  ctaBanner: {
    title: 'Platform Security',
    description:
      'Additional security features and controls are built into GitHub, including protection for user accounts, branches, tags, and pushes, SBOMs and Artifact Attestations for SLSA L3 builds.',
    cta: {
      label: 'See pricing',
      // TODO: Update once known
      href: '#',
    },
  },
  faq: {
    title: 'Frequently asked questions',
    items: FAQ_ITEMS,
  },
} as const

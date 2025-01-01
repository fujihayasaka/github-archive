import {InfinityIcon, SyncIcon} from '@primer/octicons-react'
import {analyticsEvent} from '../../../../lib/analytics'

export interface CellDetails {
  icon: JSX.Element
  text: string | JSX.Element
}

export interface Feature {
  title: string
  description?: string | JSX.Element
  free: boolean | CellDetails
  pro: boolean | CellDetails
  business: boolean | CellDetails
  enterprise: boolean | CellDetails
  label?: string
  footnote?: string
}

export interface FeatureGroup {
  title: string
  features: Feature[]
}

interface FeatureFlags {
  site_copilot_plans_ga?: boolean
}

// Set type as array of Feature
function chatFeatures(featureFlags: FeatureFlags): Feature[] {
  return [
    {
      title: 'Messages and interactions',
      free: {
        icon: <SyncIcon className="lp-LimitedIcon" />,
        text: 'Up to 50 per month',
      },
      pro: {
        icon: <InfinityIcon />,
        text: 'Unlimited',
      },
      business: {
        icon: <InfinityIcon />,
        text: 'Unlimited',
      },
      enterprise: {
        icon: <InfinityIcon />,
        text: 'Unlimited',
      },
    },
    {
      title: 'Access to OpenAI GPT-4o',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
    },
    {
      title: 'Access to OpenAI GPT-4.5',
      free: false,
      pro: false,
      business: false,
      enterprise: true,
      label: 'Preview',
    },
    {
      label: featureFlags.site_copilot_plans_ga ? '' : 'Preview',
      title: 'Access to Anthropic Claude 3.5 Sonnet',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
    },
    {
      label: 'Preview',
      title: 'Access to Anthropic Claude 3.7 Sonnet',
      free: false,
      pro: true,
      business: true,
      enterprise: true,
    },
    {
      label: featureFlags.site_copilot_plans_ga ? '' : 'Preview',
      title: 'Access to OpenAI o1',
      free: false,
      pro: true,
      business: true,
      enterprise: true,
    },
    {
      label: featureFlags.site_copilot_plans_ga ? '' : 'Preview',
      title: 'Access to OpenAI o3-mini',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
    },
    {
      title: 'Access to Google Gemini 2.0 Flash',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
      label: featureFlags.site_copilot_plans_ga ? '' : 'Preview',
    },
    {
      title: 'Context-aware coding support and explanations',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
    },
    {
      title: 'Debugging and security remediation assistance',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
    },
    {
      title: 'Access to knowledge from top open source repositories',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
    },
    {
      title: 'Generate tests, docs, and more with slash commands',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
    },
    {
      title: 'Answers about issues, PRs, discussions, files, commits, etc.',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
    },
    {
      title: 'Web search powered by Bing',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
    },
    {
      title: 'Explain failed Actions jobs',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
      label: 'Preview',
    },
    {
      title: 'Multi-file editing in VS Code',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
      label: 'Preview',
    },
    {
      title: 'Switch between models',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
      label: 'Preview',
    },
    {
      title: 'Add images to prompts',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
      label: 'Preview',
    },
  ]
}

function codeCompletionFeatures(): Feature[] {
  return [
    {
      title: 'Real-time code suggestions',
      free: {
        icon: <SyncIcon className="lp-LimitedIcon" />,
        text: 'Up to 2,000 per month',
      },
      pro: {
        icon: <InfinityIcon />,
        text: 'Unlimited',
      },
      business: {
        icon: <InfinityIcon />,
        text: 'Unlimited',
      },
      enterprise: {
        icon: <InfinityIcon />,
        text: 'Unlimited',
      },
    },
    {
      title: 'Next edit suggestions',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
      label: 'Preview',
    },
    {
      title: 'Comments to code',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
    },
  ]
}

function customizationFeatures(): Feature[] {
  return [
    {
      title: 'Tailor chat conversations to your private codebase (unlimited repositories indexed)',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
    },
    {
      title: 'Unlimited integrations with GitHub Copilot Extensions',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
      label: 'Preview',
    },
    {
      title: 'Build a private extension for internal tooling',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
      label: 'Preview',
    },
    {
      title: 'Personalize responses with custom instructions',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
      label: 'Preview',
    },
    {
      title: 'Prompt files to store and share reusable instructions',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
      label: 'Preview',
    },
    {
      title: 'Attach knowledge bases to chat for organizational context',
      free: false,
      pro: false,
      business: false,
      enterprise: true,
    },
    {
      title: 'Fine-tuned models for code completion (coming soon as add-on)',
      free: false,
      pro: false,
      business: false,
      enterprise: true,
    },
    {
      title: 'Set coding guidelines for code review',
      free: false,
      pro: false,
      business: false,
      enterprise: true,
    },
  ]
}

const aiNativeExperiencesFeatures: Feature[] = [
  {
    title: 'Inline chat and prompt suggestions',
    free: true,
    pro: true,
    business: true,
    enterprise: true,
  },
  {
    title: 'Slash commands and context variables',
    free: true,
    pro: true,
    business: true,
    enterprise: true,
  },
  {
    title: 'Commit message generation',
    free: true,
    pro: true,
    business: true,
    enterprise: true,
  },
  {
    title: 'Summaries for pull requests',
    free: false,
    pro: true,
    business: true,
    enterprise: true,
  },
  {
    title: 'Code feedback in VS Code',
    free: true,
    pro: true,
    business: true,
    enterprise: true,
    label: 'Preview',
  },
  {
    title: 'Explanations in Visual Studio’s Quick Info',
    free: true,
    pro: true,
    business: true,
    enterprise: true,
  },
  {
    title: 'Debug assistant in Visual Studio',
    free: true,
    pro: true,
    business: true,
    enterprise: true,
  },
  {
    title: 'Upgrade assistant for Java in VS Code',
    free: false,
    pro: true,
    business: true,
    enterprise: true,
    label: 'Preview',
  },
  {
    title: 'Code review in GitHub',
    free: false,
    pro: true,
    business: true,
    enterprise: true,
    label: 'Preview',
  },
  {
    title: 'Copilot Workspace in pull requests',
    free: false,
    pro: true,
    business: true,
    enterprise: true,
    label: 'Preview',
  },
  {
    title: 'Technical Preview access to Copilot Workspace',
    free: false,
    pro: true,
    business: true,
    enterprise: true,
  },
]

function devEnvFeatures(): Feature[] {
  return [
    {
      title: 'Editors and IDEs',
      description: (
        <>
          <span className="d-none d-md-inline"> - </span>
          <a
            href="https://docs.github.com/en/copilot/managing-copilot/configure-personal-settings/installing-the-github-copilot-extension-in-your-environment"
            className="lp-Link--inline d-block d-md-inline lp-Link--muted"
            target="_blank"
            rel="noreferrer"
            {...analyticsEvent({
              action: 'learn_more',
              tag: 'link',
              context: 'education_pro_plan',
              location: 'offer_cards',
            })}
          >
            See all supported editors
          </a>
        </>
      ),
      free: true,
      pro: true,
      business: true,
      enterprise: true,
    },
    {
      title: 'github.com',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
    },
    {
      title: 'GitHub Mobile',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
    },
    {
      title: 'GitHub CLI',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
    },
    {
      title: 'Windows Terminal',
      free: true,
      pro: true,
      business: true,
      enterprise: true,
    },
  ]
}

const managementPoliciesFeatures: Feature[] = [
  {
    title: 'Public code filter with code referencing',
    free: true,
    pro: true,
    business: true,
    enterprise: true,
  },
  {
    title: 'User management',
    free: false,
    pro: false,
    business: true,
    enterprise: true,
  },
  {
    title: 'Data excluded from training by default',
    free: false,
    pro: false,
    business: true,
    enterprise: true,
  },
  {
    title: 'Enterprise-grade security',
    free: false,
    pro: false,
    business: true,
    enterprise: true,
  },
  {
    title: 'IP indemnity',
    free: false,
    pro: false,
    business: true,
    enterprise: true,
  },
  {
    title: 'Content exclusions',
    free: false,
    pro: false,
    business: true,
    enterprise: true,
  },
  {
    title: 'SAML SSO authentication',
    free: false,
    pro: false,
    business: true,
    enterprise: true,
    footnote: '1',
  },
  {
    title: 'Usage metrics',
    free: false,
    pro: false,
    business: true,
    enterprise: true,
  },
  {
    title: 'Requires GitHub Enterprise Cloud',
    free: false,
    pro: false,
    business: false,
    enterprise: true,
  },
]

export function allFeatures(featureFlags: FeatureFlags): FeatureGroup[] {
  return [
    {
      title: 'Chat',
      features: chatFeatures(featureFlags),
    },
    {
      title: 'Code completion',
      features: codeCompletionFeatures(),
    },
    {
      title: 'Customization',
      features: customizationFeatures(),
    },
    {
      title: 'AI-native experiences',
      features: aiNativeExperiencesFeatures,
    },
    {
      title: 'Supported environments',
      features: devEnvFeatures(),
    },
    {
      title: 'Management and policies',
      features: managementPoliciesFeatures,
    },
  ]
}

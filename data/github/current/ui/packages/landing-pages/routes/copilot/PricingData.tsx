export interface Feature {
  title: string
  individual: boolean
  business: boolean
  enterprise: boolean
  label?: string
  footnote?: string
}

export interface FeatureGroup {
  title: string
  features: Feature[]
}

// Set type as array of Feature
const chatFeatures: Feature[] = [
  {
    title: 'Unlimited messages and interactions',
    individual: true,
    business: true,
    enterprise: true,
  },
  {
    title: 'Context-aware coding support and explanations',
    individual: true,
    business: true,
    enterprise: true,
  },
  {
    title: 'Debugging and security remediation assistance',
    individual: true,
    business: true,
    enterprise: true,
  },
  {
    title: 'Access to knowledge from top open source repositories',
    individual: true,
    business: true,
    enterprise: true,
    footnote: '2',
  },
  {
    title: 'Generate tests, docs, and more with slash commands',
    individual: true,
    business: true,
    enterprise: true,
  },
  {
    title: 'Web search powered by Bing',
    individual: true,
    business: true,
    enterprise: true,
    label: 'Preview',
  },
  {
    title: 'Explain failed Actions jobs',
    individual: true,
    business: true,
    enterprise: true,
    label: 'Preview',
  },
  {
    title: 'Answers about issues, PRs, discussions, files, commits, etc.',
    individual: true,
    business: true,
    enterprise: true,
    footnote: '2',
  },
  {
    title: 'Multi-file editing in VS Code',
    individual: true,
    business: true,
    enterprise: true,
    label: 'Preview',
  },
  {
    title: 'Switch between models',
    individual: true,
    business: true,
    enterprise: true,
    label: 'Preview',
  },
]

const codeCompletionFeatures: Feature[] = [
  {
    title: 'Real-time code suggestions',
    individual: true,
    business: true,
    enterprise: true,
  },
  {
    title: 'Comments to code',
    individual: true,
    business: true,
    enterprise: true,
  },
]

const customizationFeatures: Feature[] = [
  {
    title: 'Tailor chat conversations to your private codebase (up to 5/50/unlimited repos)',
    individual: true,
    business: true,
    enterprise: true,
    footnote: '2',
  },
  {
    title: 'Unlimited integrations with GitHub Copilot Extensions',
    individual: true,
    business: true,
    enterprise: true,
    label: 'Preview',
  },
  {
    title: 'Build a private extension for internal tooling',
    individual: true,
    business: true,
    enterprise: true,
    label: 'Preview',
  },
  {
    title: 'Personalize responses with custom instructions',
    individual: true,
    business: true,
    enterprise: true,
    label: 'Preview',
  },
  {
    title: 'Attach knowledge bases to chat for organizational context',
    individual: false,
    business: false,
    enterprise: true,
  },
  {
    title: 'Fine-tuned models for code completion (coming soon as add-on)',
    individual: false,
    business: false,
    enterprise: true,
  },
  {
    title: 'Set coding guidelines for code review',
    individual: false,
    business: false,
    enterprise: true,
  },
]

const aiNativeExperiencesFeatures: Feature[] = [
  {
    title: 'Inline chat and prompt suggestions',
    individual: true,
    business: true,
    enterprise: true,
  },
  {
    title: 'Slash commands and context variables',
    individual: true,
    business: true,
    enterprise: true,
  },
  {
    title: 'Commit message generation',
    individual: true,
    business: true,
    enterprise: true,
  },
  {
    title: 'Summaries for pull requests, issues, and discussions',
    individual: true,
    business: true,
    enterprise: true,
  },
  {
    title: 'Code feedback in VS Code',
    individual: true,
    business: true,
    enterprise: true,
    label: 'Preview',
  },
  {
    title: 'Explanations in Visual Studio’s Quick Info',
    individual: true,
    business: true,
    enterprise: true,
  },
  {
    title: 'Debug assistant in Visual Studio',
    individual: true,
    business: true,
    enterprise: true,
  },
  {
    title: 'Upgrade assistant for Java in VS Code',
    individual: true,
    business: true,
    enterprise: true,
    label: 'Preview',
  },
  {
    title: 'Code review in GitHub',
    individual: true,
    business: true,
    enterprise: true,
    label: 'Preview',
  },
  {
    title: 'Copilot Workspace for pull requests',
    individual: true,
    business: true,
    enterprise: true,
    label: 'Preview',
  },
  {
    title: 'Technical Preview access to Copilot Workspace',
    individual: false,
    business: false,
    enterprise: true,
  },
]

const devEnvFeatures: Feature[] = [
  {
    title: 'Editors and IDEs',
    individual: true,
    business: true,
    enterprise: true,
  },
  {
    title: 'GitHub (github.com and mobile)',
    individual: true,
    business: true,
    enterprise: true,
  },
  {
    title: 'GitHub CLI and Windows Terminal',
    individual: true,
    business: true,
    enterprise: true,
  },
]

const managementPoliciesFeatures: Feature[] = [
  {
    title: 'Public code filter with code referencing',
    individual: true,
    business: true,
    enterprise: true,
  },
  {
    title: 'User management',
    individual: false,
    business: true,
    enterprise: true,
  },
  {
    title: 'Data excluded from training by default',
    individual: false,
    business: true,
    enterprise: true,
  },
  {
    title: 'Enterprise-grade security',
    individual: false,
    business: true,
    enterprise: true,
  },
  {
    title: 'IP indemnity',
    individual: false,
    business: true,
    enterprise: true,
  },
  {
    title: 'Content exclusions',
    individual: false,
    business: true,
    enterprise: true,
  },
  {
    title: 'SAML SSO authentication',
    individual: false,
    business: true,
    enterprise: true,
    footnote: '3',
  },
  {
    title: 'Usage metrics',
    individual: false,
    business: true,
    enterprise: true,
  },
  {
    title: 'Requires GitHub Enterprise Cloud',
    individual: false,
    business: false,
    enterprise: true,
  },
]

export const allFeatures: FeatureGroup[] = [
  {
    title: 'Chat',
    features: chatFeatures,
  },
  {
    title: 'Code completion',
    features: codeCompletionFeatures,
  },
  {
    title: 'Customization',
    features: customizationFeatures,
  },
  {
    title: 'AI-native experiences',
    features: aiNativeExperiencesFeatures,
  },
  {
    title: 'Supported environments',
    features: devEnvFeatures,
  },
  {
    title: 'Management and policies',
    features: managementPoliciesFeatures,
  },
]

import {Card} from '@primer/react-brand'
import {
  ChecklistIcon,
  CodeIcon,
  DeviceDesktopIcon,
  DeviceMobileIcon,
  HeartIcon,
  MortarBoardIcon,
  TerminalIcon,
} from '@primer/octicons-react'

export interface Item {
  label?: JSX.Element
  icon?: JSX.Element
  title: string
  description: string
  button_link: string
}

export const featuresData = [
  {
    id: 'collaborative_coding',
    items: [
      {
        title: 'GitHub Codespaces',
        description:
          'Spin up fully configured dev environments in the cloud with the full power of your favorite editor.',
        button_link: '/features/codespaces',
      },
      {
        title: 'GitHub Copilot',
        description: 'Get suggestions for whole lines of code or entire functions right inside your editor.',
        button_link: '/features/copilot',
      },
      {
        title: 'Pull requests',
        description:
          'Receive notifications of contributor changes to a repository, with specified access limits, and seamlessly merge accepted updates.',
        button_link:
          'https://docs.github.com/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/about-pull-requests',
      },
      {
        title: 'Discussions',
        description:
          'Dedicated space for your community to come together, ask and answer questions, and have open-ended conversations.',
        button_link: 'https://docs.github.com/discussions',
      },
      {
        title: 'Code search & code view',
        description: 'Rapidly search, navigate, and understand code right from GitHub.com with our powerful new tools.',
        button_link: '/features/code-search',
      },
      {
        title: 'Code review',
        description: 'Review new code, visualize changes, and merge confidently with automated status checks.',
        button_link:
          'https://docs.github.com/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests',
      },
      {
        title: 'Draft pull requests',
        description: 'Collaborate and discuss changes without a formal review or the risk of unwanted merges.',
        button_link:
          'https://docs.github.com/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/about-pull-requests#draft-pull-requests',
      },
      {
        title: 'Protected branches',
        description:
          'Enforce branch merge restrictions by requiring reviews or limiting access to specific contributors.',
        button_link:
          'https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/about-protected-branches',
      },
    ],
  },
  {
    id: 'automation',
    items: [
      {
        title: 'GitHub Actions',
        description:
          'Automate your software workflows by writing tasks and combining them to build, test, and deploy faster from GitHub.',
        button_link: 'https://docs.github.com/actions',
      },
      {
        title: 'GitHub Packages',
        description:
          'Host your own software packages or use them as dependencies in other projects, with both private and public hosting available.',
        button_link: 'https://docs.github.com/packages',
      },
      {
        title: 'APIs',
        description:
          'Create calls to get all the data and events you need within GitHub, and automatically kick off and advance your software workflows.',
        button_link: 'https://docs.github.com/get-started/exploring-integrations/about-building-integrations',
      },
      {
        title: 'GitHub Marketplace',
        description:
          'Leverage thousands of actions and applications from our community to help build, improve, and accelerate your workflows.',
        button_link: 'https://github.com/marketplace?type=actions',
      },
      {
        title: 'Webhooks',
        description:
          'Dozens of events and a webhooks API help you integrate with and automate work for your repository, organization, or application.',
        button_link:
          'https://docs.github.com/get-started/customizing-your-github-workflow/exploring-integrations/about-webhooks',
      },
      {
        title: 'GitHub-hosted runners',
        description:
          'Move automation to the cloud with on-demand Linux, macOS, Windows, ARM, and GPU environments for your workflow runs, all hosted by GitHub.',
        button_link: 'https://docs.github.com/actions/using-github-hosted-runners/about-github-hosted-runners',
      },
      {
        title: 'Self-hosted runners',
        description:
          'Gain more environments and fuller control with labels, groups, and policies to manage runs on your own machines, plus an open source runner application.',
        button_link: 'https://docs.github.com/actions/hosting-your-own-runners',
      },
      {
        title: 'Workflow visualization',
        description:
          'Map workflows, track their progression in real time, understand complex workflows, and communicate status with the rest of the team.',
        button_link: 'https://docs.github.com/actions/managing-workflow-runs/using-the-visualization-graph',
      },
      {
        title: 'Workflow templates',
        description:
          'Standardize and scale best practices and processes with preconfigured workflow templates shared across your organization.',
        button_link:
          'https://docs.github.com/actions/getting-started-with-github-actions/starting-with-preconfigured-workflow-templates',
      },
    ],
  },
  {
    id: 'security',
    items: [
      {
        title: 'Code scanning',
        description:
          'Find vulnerabilities in custom code using static analysis. Prevent new vulnerabilities from being introduced by scanning every pull request.',
        button_link:
          'https://docs.github.com/code-security/code-scanning/automatically-scanning-your-code-for-vulnerabilities-and-errors/about-code-scanning',
      },
      {
        title: 'GitHub Copilot Autofix',
        description:
          'Get notified of vulnerabilities, understand their impact, and receive code suggestions to fix them immediately.',
        button_link:
          'https://docs.github.com/en/code-security/code-scanning/managing-code-scanning-alerts/about-autofix-for-codeql-code-scanning',
      },
      {
        title: 'Security campaigns',
        description:
          'Solve your backlog of application security debt with security campaigns that target and generate autofixes for up to 1,000 alerts at a time, rapidly reducing the risk of vulnerabilities and zero-day attacks.',
        button_link:
          'https://docs.github.com/en/enterprise-cloud@latest/code-security/securing-your-organization/fixing-security-alerts-at-scale&sa=D&source=docs&ust=1729524438944416&usg=AOvVaw2kubAWlMROH_emJPRJQNWU',
      },
      {
        title: 'Secret scanning',
        description:
          'Detect hard-coded secrets in your public and private repositories, and revoke them to secure access to your services.',
        button_link: 'https://docs.github.com/code-security/secret-scanning/about-secret-scanning',
      },
      {
        title: 'GitHub Copilot secret scanning',
        description:
          'Additional AI capabilities to detect elusive secrets like passwords and personally identifying information.',
        button_link:
          'https://docs.github.com/en/enterprise-cloud@latest/code-security/secret-scanning/using-advanced-secret-scanning-and-push-protection-features/generic-secret-detection/responsible-ai-generic-secrets',
      },
      {
        title: 'Dependency graph',
        description:
          'View the packages your project relies on, the repositories that depend on them, and any vulnerabilities detected in their dependencies.',
        button_link:
          'https://docs.github.com/code-security/supply-chain-security/understanding-your-software-supply-chain/about-the-dependency-graph',
      },
      {
        title: 'Dependabot alerts',
        description:
          'Receive alerts when new vulnerabilities affect your repositories, with GitHub detecting and notifying you of vulnerable dependencies in both public and private repositories.',
        button_link:
          'https://docs.github.com/code-security/dependabot/dependabot-alerts/about-dependabot-alerts#github-dependabot-alerts-for-vulnerable-dependencies',
      },
      {
        title: 'Dependabot security and version updates',
        description:
          'Keep your supply chain secure by automatically opening pull requests that update vulnerable or out-of-date dependencies.',
        button_link:
          'https://docs.github.com/code-security/dependabot/dependabot-security-updates/configuring-dependabot-security-updates',
      },
      {
        title: 'Dependency review',
        description: 'Assess the security impact of new dependencies in pull requests before merging.',
        button_link:
          'https://docs.github.com/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/reviewing-dependency-changes-in-a-pull-request',
      },
      {
        title: 'GitHub security advisories',
        description:
          'Privately report, discuss, fix, and publish information about security vulnerabilities found in open source repositories.',
        button_link:
          'https://docs.github.com/code-security/security-advisories/repository-security-advisories/about-repository-security-advisories',
      },
      {
        title: 'Private vulnerability reporting',
        description:
          'Enable your public repository to privately receive vulnerability reports from the community and collaborate on solutions.',
        button_link:
          'https://docs.github.com/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability',
      },
      {
        title: 'GitHub Advisory Database',
        description:
          "Browse or search GitHub's database of known vulnerabilities, featuring curated CVEs and security advisories linked to the GitHub dependency graph.",
        button_link:
          'https://docs.github.com/code-security/security-advisories/global-security-advisories/browsing-security-advisories-in-the-github-advisory-database#about-the-github-advisory-database',
      },
    ],
  },
  {
    id: 'client_apps',
    items: [
      {
        icon: <Card.Icon icon={<DeviceMobileIcon />} color="purple" />,
        title: 'GitHub Mobile',
        description: 'Take your projects, ideas, and code to go with fully native mobile and tablet experiences.',
        button_link: '/mobile',
      },
      {
        icon: <Card.Icon icon={<TerminalIcon />} color="purple" />,
        title: 'GitHub CLI',
        description:
          "Manage issues and pull requests from the terminal, where you're already working with Git and your code.",
        button_link: 'https://cli.github.com',
      },
      {
        icon: <Card.Icon icon={<DeviceDesktopIcon />} color="purple" />,
        title: 'GitHub Desktop',
        description:
          'Simplify your development workflow with a GUI to visualize, commit, and push changes—no command line needed.',
        button_link: 'https://desktop.github.com',
      },
    ],
  },
  {
    id: 'project_management',
    items: [
      {
        title: 'GitHub Projects',
        description: 'Create a customized view of your issues and pull requests to plan and track your work.',
        button_link:
          'https://docs.github.com/issues/planning-and-tracking-with-projects/learning-about-projects/about-projects',
      },
      {
        title: 'GitHub Issues',
        description:
          'Track bugs, enhancements, and other requests, prioritize work, and communicate with stakeholders as changes are proposed and merged.',
        button_link: 'https://docs.github.com/issues',
      },
      {
        title: 'Milestones',
        description:
          'Track progress on groups of issues or pull requests in a repository, and map groups to overall project goals.',
        button_link: 'https://docs.github.com/issues/using-labels-and-milestones-to-track-work/about-milestones',
      },
      {
        title: 'Charts and insights',
        description:
          "Leverage insights to visualize your projects by creating and sharing charts built from your project's data.",
        button_link:
          'https://docs.github.com/issues/planning-and-tracking-with-projects/viewing-insights-from-your-project',
      },
      {
        title: 'Org dependency insights',
        description:
          'View vulnerabilities, licenses, and other important information for the open source projects your organization depends on.',
        button_link:
          'https://docs.github.com/enterprise-cloud@latest/organizations/collaborating-with-groups-in-organizations/viewing-insights-for-your-organization#viewing-organization-dependency-insights',
      },
      {
        title: 'Repository insights',
        description:
          'Use data about activity, trends, and contributions within your repositories, to make data-driven improvements to your development cycle.',
        button_link:
          'https://docs.github.com/repositories/viewing-activity-and-data-for-your-repository/viewing-a-summary-of-repository-activity',
      },
      {
        title: 'Wikis',
        description:
          'Host project documentation in a wiki within your repository, allowing contributors to easily edit it on the web or locally.',
        button_link: 'https://docs.github.com/communities/documenting-your-project-with-wikis/about-wikis',
      },
    ],
  },
  {
    id: 'team_administration',
    items: [
      {
        title: 'Organizations',
        description:
          'Create groups of user accounts that own repositories and manage access on a team-by-team or individual user basis.',
        button_link: 'https://docs.github.com/organizations',
      },
      {
        title: 'Teams',
        description:
          "Organize your members to mirror your company's structure, with cascading access to permissions and mentions.",
        button_link: 'https://docs.github.com/organizations/organizing-members-into-teams/about-teams',
      },
      {
        title: 'Team sync',
        description:
          'Enable team synchronization between your identity provider and your organization on GitHub, including Entra ID and Okta.',
        button_link:
          'https://docs.github.com/enterprise-cloud@latest/organizations/managing-saml-single-sign-on-for-your-organization/managing-team-synchronization-for-your-organization',
      },
      {
        title: 'Custom roles',
        description:
          "Define users' access level to your code, data, and settings based on their role in your organization.",
        button_link: 'https://docs.github.com/get-started/learning-about-github/access-permissions-on-github',
      },
      {
        title: 'Custom repository roles',
        description:
          'Ensure members have only the permissions they need by creating custom roles with fine-grained permission settings.',
        button_link:
          'https://docs.github.com/enterprise-cloud@latest/organizations/managing-peoples-access-to-your-organization-with-roles/managing-custom-repository-roles-for-an-organization',
      },
      {
        title: 'Domain verification',
        description:
          "Verify your organization's identity on GitHub and display that verification through a profile badge.",
        button_link:
          'https://docs.github.com/enterprise-cloud@latest/organizations/managing-organization-settings/verifying-or-approving-a-domain-for-your-organization',
      },
      {
        title: 'Compliance reports',
        description:
          'Take care of your security assessment and certification needs by accessing GitHub’s cloud compliance reports, such as our SOC reports and Cloud Security Alliance CAIQ self-assessments (CSA CAIQ).',
        button_link:
          'https://docs.github.com/enterprise-cloud@latest/admin/overview/accessing-compliance-reports-for-your-enterprise',
      },
      {
        title: 'Audit log',
        description:
          'Quickly review the actions performed by members of your organization. Monitor access, permission changes, user changes, and other events.',
        button_link:
          'https://docs.github.com/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/reviewing-the-audit-log-for-your-organization#using-the-audit-log-api',
      },
      {
        title: 'Repository rules',
        description:
          "Enhance your organization's security with scalable source code protections, and use rule insights to easily review how and why code changes occurred in your repositories.",
        button_link:
          'https://docs.github.com/enterprise-cloud@latest/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets',
      },
      {
        label: <Card.Label color="blue">Requires GitHub Enterprise</Card.Label>,
        title: 'Enterprise accounts',
        description:
          'Enable collaboration between your organization and GitHub environments with a single point of visibility and management via an enterprise account.',
        button_link: 'https://docs.github.com/enterprise-cloud@latest/admin/overview/about-enterprise-accounts',
      },
      {
        label: <Card.Label color="blue">Requires GitHub Enterprise</Card.Label>,
        title: 'GitHub Connect',
        description:
          'Share features and workflows between your GitHub Enterprise Server instance and GitHub Enterprise Cloud.',
        button_link:
          'https://docs.github.com/enterprise-server@latest/admin/configuration/configuring-github-connect/about-github-connect',
      },
      {
        label: <Card.Label color="blue">Requires GitHub Enterprise</Card.Label>,
        title: 'SAML',
        description:
          'Securely control access to organization resources like repositories, issues, and pull requests with SAML, while allowing users to authenticate with their GitHub usernames.',
        button_link:
          'https://docs.github.com/github-ae@latest/admin/identity-and-access-management/using-saml-for-enterprise-iam/about-saml-for-enterprise-iam',
      },
      {
        label: <Card.Label color="blue">Requires GitHub Enterprise</Card.Label>,
        title: 'LDAP',
        description:
          'Centralize repository management. LDAP is one of the most common protocols used to integrate third-party software with large company user directories.',
        button_link:
          'https://docs.github.com/enterprise-server@latest/admin/identity-and-access-management/using-ldap-for-enterprise-iam/using-ldap',
      },
      {
        label: <Card.Label color="blue">Requires GitHub Enterprise</Card.Label>,
        title: 'Enterprise Managed Users',
        description:
          'Manage the lifecycle and authentication of users on GitHub Enterprise Cloud from your identity provider (IdP).',
        button_link:
          'https://docs.github.com/en/enterprise-cloud@latest/admin/managing-iam/understanding-iam-for-enterprises/about-enterprise-managed-users',
      },
      {
        label: <Card.Label color="blue">Requires GitHub Enterprise</Card.Label>,
        title: 'Bring your own identity provider for Enterprise Managed Users',
        description:
          'Use the SSO and SCIM providers of your choice for Enterprise Managed Users, separate from one another, for a more flexible approach to user lifecycle management.',
        button_link:
          'https://docs.github.com/en/enterprise-cloud@latest/admin/managing-iam/provisioning-user-accounts-with-scim/provisioning-users-and-groups-with-scim-using-the-rest-api',
      },
    ],
  },
  {
    id: 'community',
    items: [
      {
        icon: <Card.Icon icon={<HeartIcon />} color="pink" />,
        title: 'GitHub Sponsors',
        description:
          'Financially support the open source projects your code depends on. Sponsor a contributor, maintainer, or project with one time or recurring contributions.',
        button_link: 'https://github.com/sponsors',
      },
      {
        icon: <Card.Icon icon={<ChecklistIcon />} color="pink" />,
        title: 'GitHub Skills',
        description:
          'Learn new skills by completing tasks and projects directly within GitHub, guided by our friendly bot.',
        button_link: 'https://skills.github.com',
      },
      {
        icon: <Card.Icon icon={<CodeIcon />} color="pink" />,
        title: 'Electron',
        description:
          'Write cross-platform desktop applications using JavaScript, HTML, and CSS with the Electron framework, based on Node.js and Chromium.',
        button_link: 'https://www.electronjs.org/docs/latest',
      },
      {
        icon: <Card.Icon icon={<MortarBoardIcon />} color="pink" />,
        title: 'Education',
        description:
          'GitHub Education is a commitment to bringing tech and open source collaboration to students and educators across the globe.',
        button_link: 'https://github.com/education',
      },
    ],
  },
]

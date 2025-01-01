import {
  FileIcon,
  VersionsIcon,
  TerminalIcon,
  ToolsIcon,
  ZapIcon,
  type Icon,
  BookIcon,
  PeopleIcon,
  MarkGithubIcon,
  CopilotIcon,
} from '@primer/octicons-react'

export interface CardData {
  title: string
  description: string
  icon: Icon
  cta: {
    label: string
    url: string
  }
}

export const HERO_EXTENSIONS = [
  {
    image: '/images/modules/site/copilot/extensions/logos/sentry.svg',
    alt: 'Sentry logo.',
  },
  {
    image: '/images/modules/site/copilot/extensions/logos/jfrog.svg',
    alt: 'Jfrog logo.',
  },
  {
    image: '/images/modules/site/copilot/extensions/logos/launchdarkly.svg',
    alt: 'LaunchDarkly logo',
  },
  {
    image: '/images/modules/site/copilot/extensions/logos/atlassian.svg',
    alt: 'Atlassian logo.',
  },
  {
    image: '/images/modules/site/copilot/extensions/logos/perplexity.svg',
    alt: 'PerplexityAI logo.',
  },
  {
    image: '/images/modules/site/copilot/extensions/logos/docker.svg',
    alt: 'Docker logo.',
  },
  {
    image: '/images/modules/site/copilot/extensions/logos/stack-overflow.svg',
    alt: 'Stackoverflow logo.',
  },
  {
    image: '/images/modules/site/copilot/extensions/logos/http-fetch.svg',
    alt: 'Http-fetch logo.',
  },
  {
    image: '/images/modules/site/copilot/extensions/logos/mermaid-chart.svg',
    alt: 'Mermaid Chart logo.',
  },
  {
    image: '/images/modules/site/copilot/extensions/logos/teams.svg',
    alt: 'Teams logo.',
  },
]

export const COPY = {
  hero: {
    title: 'Build and deploy with the tools you love in Copilot Chat',
    description:
      'Copilot Extensions integrate your external dev tools into Copilot Chat. <span>All you need is an API.</span>',
    cta1: {
      label: 'Explore extensions',
      url: 'https://github.com/marketplace?type=apps&copilot_app=true',
    },
    cta2: {
      label: 'Build an extension',
      url: '#resources',
    },
    ui: {
      windowTitle: 'Ask Copilot',
      chatTitle: 'Ask Copilot',
      chatWelcome: {
        greeting: 'Hi there!',
        question: 'How can I help?',
      },
      messagePlaceholder: 'Ask Copilot',
      extensions: {
        docker: {
          name: 'Docker',
          handle: 'docker',
          messagePlaceholder: 'Can you help me find vulnerabilities in my project?',
        },
        mermaidchart: {
          name: 'Mermaid Chart',
          handle: 'mermaid-chart',
          messagePlaceholder: 'Visualize this database schema from my SQL file',
        },
        models: {
          name: 'Models',
          handle: 'models',
          messagePlaceholder: 'What models are available?',
        },
        perplexityai: {
          name: 'PerplexityAI',
          handle: 'perplexityai',
          messagePlaceholder: 'Where can I deploy my app?',
        },
        sentry: {
          name: 'Sentry',
          handle: 'sentry',
          messagePlaceholder: 'Show me my most recent issues',
        },
      },
      aria: {
        description: 'Interactive Copilot Extensions example',
        // TODO: Update once known
        mention: 'Toggle the extensions menu',
        // TODO: Update once known
        menu: 'Extensions menu',
        copilotLogo: 'GitHub Copilot logo',
      },
    },
    extensions: {
      aria: {
        copilotLogo: 'GitHub Copilot logo',
      },
    },
  },
  features: {
    label: 'Features',
    title: 'Your tools. Your workflow.<br class="lp-breakWhenWide" /> All within Copilot Chat',
    items: [
      {
        title: 'All you have to do is ask',
        description:
          'Forget memorizing obscure syntax or terminology. Stay in the flow and use natural language to interact with your tools though Copilot Chat in VS Code, Visual Studio, JetBrains IDEs, GitHub.com, or GitHub Mobile.',
        image: {
          url: '/images/modules/site/copilot/extensions/features-river-1.webp',
          alt: "User interface of a chat window with Docker, showing example questions like 'Can you help me find vulnerabilities in my project?' and 'How would I use Docker to containerize this project?' A text input field displays a typed message: '@docker What can I ask you to help with?",
        },
      },
      {
        title: 'Homegrown tech, meet private extensions',
        description:
          'Leverage context from your internal developer tools, execute workflows, and stay aligned with your organization’s best practices and data policies.',
        image: {
          url: '/images/modules/site/copilot/extensions/features-river-2.webp',
          alt: "User interface of a chat window with a private GitHub repository named 'GitHub/GitHub-demo.' The conversation includes a user named 'monalisa' asking how to manage Kubernetes for a project. The repository responds with information about 'Hubbernetes,' a collection of GitHub-developed applications for managing Kubernetes clusters, and provides links to a Kubernetes repository and template. The input field is shown with '@GitHub-internal' typed.",
        },
      },
      {
        title: 'There’s an extension for that',
        description: 'Find extensions—from API development to application monitoring—right in GitHub Marketplace.',
        image: {
          url: '/images/modules/site/copilot/extensions/features-river-3.webp',
          alt: 'Grid of icons representing various extensions available in the GitHub Marketplace. Icons displayed include logos for Sentry, Stackoverflow, Octopus Deploy, LaunchDarkly, ReadMe, Docker, Arm, Perplexity, Mermaid Chart, Microsoft Teams, and other tools.',
        },
        link: {
          label: 'Explore extensions',
          url: 'https://github.com/marketplace?type=apps&copilot_app=true',
        },
      },
    ],
  },
  getStarted: {
    label: 'Resources',
    title: 'Want to build your own?<br class="lp-breakWhenWide" /> Get started with the essentials',
    cards: [
      {
        title: 'Quick start samples',
        description: 'View code samples and the SDK to learn how to authorize your extension, call APIs, and more.',
        icon: ZapIcon,
        cta: {
          label: 'Explore samples',
          url: 'https://github.com/copilot-extensions/',
        },
      },
      {
        title: 'Documentation',
        description: 'All the information you’ll need to build your first extension.',
        icon: FileIcon,
        cta: {
          label: 'Read the docs',
          url: 'https://docs.github.com/en/copilot/building-copilot-extensions/about-building-copilot-extensions',
        },
      },
      {
        title: 'Guided tutorials',
        description: 'Get step-by-step walkthroughs and videos to set up your GitHub Copilot Extensions in no time.',
        icon: VersionsIcon,
        cta: {
          label: 'Get started',
          url: 'http://resources.github.com/learn/pathways/copilot/extensions/essentials-of-github-copilot-extensions/',
        },
      },
      {
        title: 'GitHub Copilot Extension debug CLI',
        description: 'Build, test and debug your extension directly from your terminal with our CLI tool.',
        icon: TerminalIcon,
        cta: {
          label: 'Read the docs',
          url: 'https://github.com/copilot-extensions/gh-debug-cli',
        },
      },
      {
        title: 'Customize GitHub Copilot to your organization',
        description:
          'Develop private Copilot Extensions that integrate seamlessly with your internal tools, data, and processes.',
        icon: ToolsIcon,
        cta: {
          label: 'Get started',
          url: 'https://docs.github.com/en/copilot/building-copilot-extensions/managing-the-availability-of-your-copilot-extension',
        },
      },
      {
        title: 'Integrate GitHub Copilot with your VS Code Chat participant',
        description:
          'Have a VS Code Chat participant or planning to build one? You can extend its functionality with Copilot Extensions, just like with GitHub Apps.',
        icon: CopilotIcon,
        cta: {
          label: 'Learn more',
          url: 'https://code.visualstudio.com/api/extension-guides/chat',
        },
      },
    ],
  },
  testimonial: {
    quote: `This is the future of software development, where developers spend less time searching and more time building. <span>Working in natural language, they can write code, retrieve data, and solve problems, all using a single intuitive workflow.</span>`,
    name: 'Tillman Elser',
    position: 'Engineering Manager, Sentry',
  },
  ctaBanner: {
    title: 'Your favorite tools have entered Copilot Chat',
    cta1: {
      label: 'Explore extensions',
      url: 'https://github.com/marketplace?type=apps&copilot_app=true',
    },
    cta2: {
      label: 'Get started with Copilot',
      url: 'https://github.com/features/copilot#pricing',
    },
    aria: {
      // TODO: Update once known
      copilotHead: '',
    },
  },
  resources: {
    title: 'Additional resources',
    cards: [
      {
        title: 'Become a GitHub Technology Partner',
        description:
          'Get the VIP treatment with priority access to technical support, early previews to new features, and more.',
        icon: MarkGithubIcon,
        cta: {
          label: 'Join now',
          url: 'https://partner.github.com/technology-partners',
        },
      },
      {
        title: 'Meet the companies who build with GitHub',
        description: 'Leading organizations choose GitHub to plan, build, secure, and ship software.',
        icon: PeopleIcon,
        cta: {
          label: 'Read customer stories',
          url: 'https://github.com/customer-stories/enterprise?feature=GitHub%2BCopilot#browse',
        },
      },
      {
        title: 'Keep up with the latest on GitHub and AI',
        description: 'Check out the GitHub Blog for tips, technical guides, best practices, and more.',
        icon: BookIcon,
        cta: {
          label: 'Read the Blog',
          url: 'https://github.blog/ai-and-ml/github-copilot/',
        },
      },
    ],
  },
  faq: {
    title: 'Frequently asked questions',
    items: [
      {
        question: 'What are GitHub Copilot Extensions?',
        answer: [
          'GitHub Copilot Extensions are integrations that expand the capabilities of Copilot, allowing developers to interact with external tools and services directly within Copilot Chat in VS Code, Visual Studio, JetBrains IDEs, GitHub.com, and GitHub Mobile.',
        ],
      },
      {
        question: 'Who can use GitHub Copilot Extensions?',
        answer: [
          'Copilot Extensions are available to GitHub users, organizations, and enterprises with supported GitHub and Copilot plan types and the Copilot Extensions policy enabled. Extensions can be used with a Copilot Pro plan, which is available to individual GitHub users. Copilot Business and Copilot Enterprise plan customers must have a GitHub plan type that supports installing and using GitHub Apps at the organization level. Copilot Extensions are not supported on GitHub Enterprise Server.',
        ],
      },
      {
        question: 'Are GitHub Copilot Extensions free?',
        answer: [
          'Copilot Extensions are free to build. Most listed extensions on the GitHub Marketplace are also free to use. A GitHub Copilot license of any type is required to use and build extensions. Some extensions may require a paid plan for the publisher’s service.',
        ],
      },
      {
        question: 'Are GitHub Copilot Extensions high quality and secure?',
        answer: [
          'Copilot Extensions in the GitHub Marketplace are built by third parties and may vary in quality. GitHub reviews any extensions published to the Marketplace, and all publishers must be <a href="https://docs.github.com/en/apps/github-marketplace/github-marketplace-overview/applying-for-publisher-verification-for-your-organization">Verified Creators</a>. Publishers can share security and transparency to display on their extension’s listing page. Data like permissions is verified by GitHub, while other info is self-attested. We encourage customers to conduct their own security reviews and only install extensions from publishers that they trust.',
        ],
      },
      {
        question:
          'Can enterprises and organizations build private extensions? And what benefits do private extensions have?',
        answer: [
          'Yes. Enterprises and organizations can build private GitHub Copilot Extensions for internal use. These extensions are only visible and usable by the enterprise or organization that created them. Private extensions must be installed at the organization level, but can be created at the <a href="https://docs.github.com/en/enterprise-cloud@latest/admin/managing-your-enterprise-account/creating-github-apps-for-your-enterprise">enterprise</a> or organization level. They allow for the integration of proprietary tools, databases and workflows. Details on getting started can be found in the <a href="https://docs.github.com/en/copilot/building-copilot-extensions/about-building-copilot-extensions">documentation</a>.',
        ],
      },
      {
        question: 'What GitHub Copilot data is shared with the extension author when using Copilot Extensions?',
        answer: [
          'At a minimum, when using a Copilot Extension your GitHub user ID and the contents of your chat history with a specific extension and general threads are shared with the extension author. Each extension will not have access to your thread history with other extensions.',
          'Additional data can be shared depending on the permissions required for a specific extension. Users and organization owners must explicitly authorize any permissions before completing installation, which may include context from the GitHub organization account or its repositories.',
        ],
      },
      {
        question: 'What should I keep in mind while using GitHub Copilot Extensions?',
        answer: [
          'Copilot Extensions depend on our ecosystem of builders and users. The platform will continue to evolve to better support our community. Users should expect ongoing improvements and potential changes. Extensions may have varying levels of functionality and stability. We encourage users to <a href="https://github.com/copilot-extensions/user-feedback/tree/main">provide feedback</a> to help improve the platform and individual extensions.',
        ],
      },
      {
        question: "What's the difference between GitHub App Copilot Extensions and VS Code Chat Participants?",
        answer: [
          'GitHub App Copilot Extensions work across multiple platforms (VS Code, Visual Studio, JetBrains IDEs, GitHub.com and GitHub Mobile) and run server-side. GitHub App Extensibility is maintained and supported by GitHub’s product and support teams.',
          'VS Code Chat Participants (sometimes referred to as Copilot Extensions as well) provide a similar end-user experience, but they’re specific only to the VS Code environment and they run locally. They integrate more deeply with VS Code features and APIs. They offer more flexibility for individual developers. Copilot-enabled VS Code Chat Participants are maintained and supported by the VS Code team.',
        ],
      },
    ],
  },
  aria: {
    togglePlayButton: {
      play: 'Play Background Animation.',
      pause: 'Pause Background Animation.',
    },
  },
}

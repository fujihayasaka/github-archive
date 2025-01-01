import AutomationHeroVideo from './assets/videos/hero_desktop.mp4'
import AutomationHeroPosterDesktop from './assets/automation/hero_poster_desktop.webp'
import DuolingoLogo from './assets/automation/logo-duolingo.svg'
import GartnerLogo from './assets/automation/logo-gartner.svg'
import AutomationAccordion1 from './assets/automation/accordion-1.webp'
import AutomationAccordion2 from './assets/automation/accordion-2.webp'
import AutomationAccordion3 from './assets/automation/accordion-3.webp'
import AutomationAccordion4 from './assets/automation/accordion-4.webp'

import type {SectionHeroProps} from './components/SectionHero/SectionHero'

export const COPY = {
  analyticsId: 'automation',
  intro: {
    title: 'Accelerate performance',
    description:
      'With GitHub Copilot embedded throughout the platform, you can simplify your toolchain, automate tasks, and improve the developer experience.',
  },
  hero: {
    aria: {
      // TODO: Update once known
      playButton: {
        play: 'Play',
        pause: 'Pause',
      },
    },
  },
  content: {
    title: 'Work 55% faster.',
    description: ' Increase productivity with AI-powered coding assistance, including code completion, chat, and more.',
    footnote: {
      number: 1,
      // eslint-disable-next-line github/unescaped-html-literal
      text: '<a href="https://github.blog/news-insights/research/survey-ai-wave-grows/">Survey: The AI wave continues to grow on software development teams, 2024.</a>',
    },
    link: {
      url: '/features/copilot',
      label: 'Explore GitHub Copilot',
    },
  },
  customers: [
    {
      logo: {
        url: DuolingoLogo,
        alt: 'Duolingo',
        height: 32,
      },
      description: 'Duolingo boosts developer speed by 25% with GitHub Copilot',
      link: {
        url: '/customer-stories/duolingo',
        label: 'Read customer story',
      },
    },
    {
      logo: {
        url: GartnerLogo,
        alt: 'Gartner',
        height: 24,
      },
      description: '2024 Gartner® Magic Quadrant™ for AI Code Assistants',
      link: {
        url: 'https://www.gartner.com/doc/reprints?id=1-2IKO4MPE&ct=240819&st=sb',
        label: 'Read report',
      },
    },
  ],
  accordion: {
    items: [
      {
        title: 'Automate any workflow',
        description: 'Optimize your process with simple and secured CI/CD.',
        link: {
          label: 'Discover GitHub Actions',
          url: '/features/actions',
        },
        visual: {
          url: AutomationAccordion1,
          alt: 'A list of workflows displays a heading ‘45,167 workflow runs’ at the top. Below are five rows of completed workflows accompanied by their completion time and their duration formatted in minutes and seconds.',
        },
      },
      {
        title: 'Get up and running in seconds',
        description: 'Start building instantly with a comprehensive dev environment in the cloud.',
        link: {
          label: 'Check out GitHub Codespaces',
          url: '/features/codespaces',
        },
        visual: {
          url: AutomationAccordion2,
          alt: 'A GitHub Codespaces setup for the landing page of a game called OctoInvaders. On the left is a code editor with some HTML and Javascript files open. On the right is a live render of the page. In front of this split editor window is a screenshot of two active GitHub Codespaces environments with their branch names and a button to ‘Create codespace on main.’',
        },
      },
      {
        title: 'Build on the go',
        description: 'Manage projects and chat with GitHub Copilot from anywhere.',
        link: {
          label: 'Download GitHub Mobile',
          url: '/mobile',
        },
        visual: {
          url: AutomationAccordion3,
          alt: 'Two smartphone screens side by side. The left screen shows a Notification inbox, listing issues and pull requests from different repositories like TensorFlow and GitHub’s OctoArcade octoinvaders. The right screen shows a new conversation in GitHub Copilot chat.',
        },
      },
      {
        title: 'Integrate the tools you love',
        description: 'Sync with 17,000+ integrations and a growing library of Copilot Extensions.',
        link: {
          label: 'Visit GitHub Marketplace',
          url: '/marketplace',
        },
        visual: {
          url: AutomationAccordion4,
          alt: 'A grid of fifty app tiles displays logos for integrations and extensions for companies like Stripe, Slack, and Docker. The tiles extend beyond the bounds of the image to indicate a wide array of apps. ',
        },
      },
    ],
  },
}

export const HERO_VISUALS: SectionHeroProps['visuals'] = [
  {
    type: 'video',
    url: {
      desktop: AutomationHeroVideo,
    },
    poster: {
      desktop: AutomationHeroPosterDesktop,
    },
    alt: 'A Copilot chat window with extensions enabled. The user inputs the @ symbol to reveal a list of five Copilot Extensions. @Sentry is selected from the list, which shifts the window to a chat directly with that extension. There are three sample prompts at the bottom of the chat window, allowing the user to Get incident information, Edit status on incident, or List the latest issues. The last one is activated to send the prompt: @Sentry List the latest issues. The extension then lists several new issues and their metadata.',
  },
]

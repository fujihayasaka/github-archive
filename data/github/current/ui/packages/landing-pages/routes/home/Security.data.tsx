import SecurityHero from './assets/security/hero.webp'
import SecurityPillar1 from './assets/security/pillar-1.webp'
import SecurityPillar2 from './assets/security/pillar-2.webp'
import SecurityPillar3 from './assets/security/pillar-3.webp'

import type {SectionHeroProps} from './components/SectionHero/SectionHero'

export const COPY = {
  analyticsId: 'security',
  intro: {
    title: 'Built-in application security <br class="lp-breakText" /> where found means fixed',
    description: 'Use AI to find and fix vulnerabilities—freeing your teams to ship more secure software faster.',
  },
  hero: {
    title: 'Apply fixes in seconds.',
    description: ' Spend less time fixing vulnerabilities and more time building features with Copilot Autofix.',
    link: {
      url: '/enterprise/advanced-security',
      label: 'Explore GitHub Advanced Security',
    },
    aria: {
      // TODO: Update once known
      playButton: {
        play: 'Play',
        pause: 'Pause',
      },
    },
  },
  topics: [
    {
      title: 'Solve security debt.',
      description:
        ' Leverage AI-assisted security campaigns to reduce application vulnerabilities and zero-day attacks.',
      link: {
        url: '/enterprise/advanced-security',
        label: 'Discover security campaigns',
      },
      visual: {
        url: SecurityPillar1,
        alt: 'A security campaign screen displays the campaign’s progress bar with 97% completed of 701 alerts. A total of 23 alerts are left with 13 in progress, and the campaign started 20 days ago. The status below shows that there are 7 days left in the campaign with a due date of November 15, 2024.',
      },
    },
    {
      title: 'Dependencies you can depend on.',
      description: ' Update vulnerable dependencies with supported fixes for breaking changes.',
      link: {
        url: '/features/security/software-supply-chain',
        label: 'Learn about Dependabot',
      },
      visual: {
        url: SecurityPillar2,
        alt: 'List of dependencies defined in a requirements .txt file.',
      },
    },
    {
      title: 'Your secrets, your business: protected. ',
      description: ' Detect, prevent, and remediate leaked secrets across your organization.',
      link: {
        url: '/features/security/code',
        label: 'Read about secret scanning',
      },
      visual: {
        url: SecurityPillar3,
        alt: 'GitHub push protection confirms and displays an active secret, and blocks the push.',
      },
    },
  ],
  statistics: [
    {
      heading: '7x faster',
      description: 'vulnerability fixes with GitHub',
      footnote: {
        number: 2,
        text: 'This 7X times factor is based on data from the industry’s longest running analysis of fix rates Veracode State of Software Security 2023, which cites the average time to fix 50% of flaws as 198 days vs. GitHub’s fix rates of 72% of flaws with in 28 days which is at a minimum of 7X faster when compared.',
      },
    },
    {
      heading: '90% coverage',
      description:
        // eslint-disable-next-line github/unescaped-html-literal
        '<a href="https://docs.github.com/en/code-security/code-scanning/managing-your-code-scanning-configuration/codeql-query-suites">of alert types in all supported languages with Copilot Autofix</a>',
    },
  ],
}

export const HERO_VISUALS: SectionHeroProps['visuals'] = [
  {
    type: 'image',
    url: {
      desktop: SecurityHero,
    },
    alt: 'Copilot Autofix identifies vulnerable code and provides an explanation, together with a secure code suggestion to remediate the vulnerability.',
  },
]

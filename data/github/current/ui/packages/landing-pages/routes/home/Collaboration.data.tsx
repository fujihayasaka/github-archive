import CollaborationHero from './assets/collaboration/hero.webp'
import CollaborationAccordion1 from './assets/collaboration/accordion-1.webp'
import CollaborationAccordion2 from './assets/collaboration/accordion-2.webp'
import CollaborationAccordion3 from './assets/collaboration/accordion-3.webp'
import CollaborationAccordion4 from './assets/collaboration/accordion-4.webp'

import type {SectionHeroProps} from './components/SectionHero/SectionHero'

export const COPY = {
  analyticsId: 'collaboration',
  intro: {
    title: 'Work together, achieve more',
    description:
      'Collaborate with your teams, use management tools that sync with your projects, and code from anywhere—all on a single, integrated platform.',
  },
  content: {
    title: 'Your workflows, your way.',
    description: ' Plan effectively with an adaptable spreadsheet that syncs with your work.',
    link: {
      url: '/features/issues',
      label: 'Jump into GitHub Projects',
    },
  },
  testimonial: {
    quote:
      'It helps us onboard new software engineers and get them productive right away. We have all our source code, issues, and pull requests in one place... GitHub is a complete platform that frees us from menial tasks and enables us to do our best work.',
    name: 'Fabian Faulhaber',
    position: 'Application manager at Mercedes-Benz',
  },
  accordion: {
    items: [
      {
        title: 'Keep track of your tasks',
        description: 'Create issues and manage projects with tools that adapt to your code.',
        link: {
          label: 'Explore GitHub Issues',
          url: '/features/issues',
        },
        visual: {
          url: CollaborationAccordion1,
          alt: 'Display of task tracking within an issue, showing the status of related sub-issues and their connection to the main issue.',
        },
      },
      {
        title: 'Share ideas and ask questions',
        description: 'Create space for open-ended conversations alongside your project.',
        link: {
          label: 'Discover GitHub Discussions',
          url: '/features/discussions',
        },
        visual: {
          url: CollaborationAccordion2,
          alt: 'A GitHub Discussions thread where a GitHub user suggests a power-up idea involving Hubot revealing a path and protecting Mona. The post has received 5 upvotes and several reactions. Below, three other users add to the discussion, suggesting Hubot could provide different power-ups depending on levels and appreciating the collaboration idea.',
        },
      },
      {
        title: 'Review code changes together',
        description: 'Create review processes that improve code quality and fit neatly into your workflow.',
        link: {
          label: 'Learn about code review',
          url: '/features/code-review',
        },
        visual: {
          url: CollaborationAccordion3,
          alt: 'Two code review approvals by helios-ackmore and amanda-knox, which are followed by three successful checks for ‘Build,’ ‘Test,’ and ‘Publish.’',
        },
      },
      {
        title: 'Fund open source projects',
        description: 'Become an open source partner and support the tools and libraries that power your work.',
        link: {
          label: 'Dive into GitHub Sponsors',
          url: '/sponsors',
        },
        visual: {
          url: CollaborationAccordion4,
          alt: 'A GitHub Sponsors popup displays ‘$15,000 a month’ with a progress bar showing 87% towards a $15,000 goal.',
        },
      },
    ],
  },
}

export const HERO_VISUALS: SectionHeroProps['visuals'] = [
  {
    type: 'image',
    url: {
      desktop: CollaborationHero,
    },
    alt: 'A project management dashboard showing tasks for the ‘OctoArcade Invaders’ project, with tasks grouped under project phase categories like ‘Prototype,’ ‘Beta,’ and ‘Launch’ in a table layout. One of the columns displays sub-issue progress bars with percentages for each issue.',
  },
]

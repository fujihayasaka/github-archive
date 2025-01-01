import Code1VideoDesktop from '../../assets/videos/code-1_desktop.mp4'
import Code1VideoMobile from '../../assets/videos/code-1_mobile.mp4'
import Code1PosterDesktop from '../../assets/carousel/code-1_poster_desktop.webp'
import Code1PosterMobile from '../../assets/carousel/code-1_poster_mobile.webp'
import Plan1Desktop from '../../assets/carousel/plan-1_desktop.webp'
import Plan1Mobile from '../../assets/carousel/plan-1_mobile.webp'
import Plan2Desktop from '../../assets/carousel/plan-2_desktop.webp'
import Plan2Mobile from '../../assets/carousel/plan-2_mobile.webp'
import Plan3Desktop from '../../assets/carousel/plan-3_desktop.webp'
import Plan3Mobile from '../../assets/carousel/plan-3_mobile.webp'
import PlanCursor from '../../assets/carousel/plan-cursor.svg'
import Collaborate1Desktop from '../../assets/carousel/collaborate-1_desktop.webp'
import Collaborate1Mobile from '../../assets/carousel/collaborate-1_mobile.webp'
import Collaborate2Desktop from '../../assets/carousel/collaborate-2_desktop.webp'
import Automate0Desktop from '../../assets/carousel/automate-0_desktop.webp'
import Automate0Mobile from '../../assets/carousel/automate-0_mobile.webp'
import Automate1Desktop from '../../assets/carousel/automate-1_desktop.webp'
import Automate1Mobile from '../../assets/carousel/automate-1_mobile.webp'
import Automate2Desktop from '../../assets/carousel/automate-2_desktop.webp'
import Automate2Mobile from '../../assets/carousel/automate-2_mobile.webp'
import Automate3Desktop from '../../assets/carousel/automate-3_desktop.webp'
import Automate3Mobile from '../../assets/carousel/automate-3_mobile.webp'
import Secure1Desktop from '../../assets/carousel/secure-1_desktop.webp'
import Secure1Mobile from '../../assets/carousel/secure-1_mobile.webp'
import Secure2Desktop from '../../assets/carousel/secure-2_desktop.webp'

export const HeroScreenId = {
  code: 'code',
  plan: 'plan',
  collaborate: 'collaborate',
  automate: 'automate',
  secure: 'secure',
} as const

export type HeroScreenId = (typeof HeroScreenId)[keyof typeof HeroScreenId]

interface HeroVisual {
  type: 'image' | 'video'
  url: {
    mobile?: string
    desktop: string
  }
  poster?: {
    mobile?: string
    desktop?: string
  }
  duration: number // seconds
  zIndex?: number
  ariaHidden?: boolean
  alt: string
  className?: string
}

interface HeroScreen {
  id: HeroScreenId
  visuals: HeroVisual[]
}

export const SCREENS: HeroScreen[] = [
  {
    id: HeroScreenId.code,
    visuals: [
      {
        type: 'video',
        url: {
          mobile: Code1VideoMobile,
          desktop: Code1VideoDesktop,
        },
        poster: {
          mobile: Code1PosterMobile,
          desktop: Code1PosterDesktop,
        },
        duration: 15,
        alt: 'A demonstration animation of a code editor using GitHub Copilot Chat, where the user requests GitHub Copilot to refactor duplicated logic and extract it into a reusable function for a given code snippet.',
      },
    ],
  },
  {
    id: HeroScreenId.plan,
    visuals: [
      {
        type: 'image',
        url: {
          mobile: Plan1Mobile,
          desktop: Plan1Desktop,
        },
        duration: 2,
        alt: 'A project management dashboard showing tasks organized by columns with progress categories like ‘Planning,’ ‘Building,’ ‘Behind,’ and ‘Complete.’',
      },
      {
        type: 'image',
        url: {
          mobile: Plan2Mobile,
          desktop: Plan2Desktop,
        },
        duration: 2,
        alt: 'A project management dashboard showing tasks organized by milestone for the ‘OctoArcade Invaders’ project, with tasks grouped under categories like ‘Engine,’ ‘Game Loop,’ and ‘Art’ in a table layout.',
      },
      {
        type: 'image',
        url: {
          mobile: Plan3Mobile,
          desktop: Plan3Desktop,
        },
        duration: 3,
        alt: 'A project management dashboard showing tasks organized by squads in the column on the left and a timeline view of tasks on the right.',
      },
      {
        type: 'image',
        url: {
          desktop: PlanCursor,
        },
        ariaHidden: true,
        duration: 0,
        alt: '',
        className: 'lp-HeroCarousel-visual-cursor',
      },
    ],
  },
  {
    id: HeroScreenId.collaborate,
    visuals: [
      {
        type: 'image',
        url: {
          mobile: Collaborate1Mobile,
          desktop: Collaborate1Desktop,
        },
        duration: 1,
        alt: `A pull request discussion displaying comments from team members requesting changes, and Copilot confirming it has implemented the CSS positioning adjustment from 'fixed' to 'sticky' to limit floating behavior.`,
      },
      {
        type: 'image',
        url: {
          desktop: Collaborate2Desktop,
        },
        duration: 2,
        alt: 'A mobile view of a pull request summary, showing Copilot as the author and listing the code changes.',
      },
    ],
  },
  {
    id: HeroScreenId.automate,
    visuals: [
      {
        type: 'image',
        url: {
          mobile: Automate1Mobile,
          desktop: Automate1Desktop,
        },
        zIndex: 3,
        duration: 1,
        alt: 'GitHub Actions workflow titled ‘matrix-build-deploy.yml’. The Build stage has completed successfully in 1 minute and 42 seconds.',
      },
      {
        type: 'image',
        url: {
          mobile: Automate2Mobile,
          desktop: Automate2Desktop,
        },
        zIndex: 2,
        duration: 1,
        alt: 'The Test stage includes builds for Linux, macOS, and Windows, all of which have also completed successfully with their respective durations.',
      },
      {
        type: 'image',
        url: {
          mobile: Automate3Mobile,
          desktop: Automate3Desktop,
        },
        zIndex: 1,
        duration: 1,
        alt: 'The final stage, Publish, shows that the publishing steps for Linux, macOS, and Windows are pending and waiting for approval.',
      },
      {
        type: 'image',
        url: {
          mobile: Automate0Mobile,
          desktop: Automate0Desktop,
        },
        zIndex: 0,
        ariaHidden: true,
        duration: 0,
        alt: '',
      },
    ],
  },
  {
    id: HeroScreenId.secure,
    visuals: [
      {
        type: 'image',
        url: {
          mobile: Secure1Mobile,
          desktop: Secure1Desktop,
        },
        duration: 1,
        alt: 'Trend graph showing a decline in critical vulnerabilities over time.',
      },
      {
        type: 'image',
        url: {
          desktop: Secure2Desktop,
        },
        duration: 2,
        alt: 'Copilot Autofix identifies vulnerable code and provides an explanation, together with a secure code suggestion to remediate the vulnerability.',
      },
    ],
  },
]

export const getScreen = (screenId: HeroScreenId) => SCREENS.find(screen => screen.id === screenId)

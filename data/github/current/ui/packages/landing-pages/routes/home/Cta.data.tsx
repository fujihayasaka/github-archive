import CtaMascotGlowStart from './assets/cta/mascots-glow-start.webp'
import CtaMascotGlowEnd from './assets/cta/mascots-glow-end.webp'

export const COPY = {
  heading: 'Millions of developers and businesses call GitHub home',
  description:
    'Whether you’re scaling your development process or just learning how to code, GitHub is where you belong. Join the world’s most widely adopted AI-powered developer platform to build the technologies that redefine what’s possible.',
  cta1: {
    label: 'Sign up for GitHub',
    url: '/signup?source=form-home-signup',
  },
  cta1LoggedIn: {
    label: 'Explore upcoming releases',
    url: '/features/preview',
  },
  cta2: {
    label: 'Try GitHub Copilot',
    subLabel: '30 days free',
    url: '/features/copilot',
  },
  visual: {
    url: {
      glowStart: CtaMascotGlowStart,
      glowEnd: CtaMascotGlowEnd,
    },
    alt: 'A subtle purple glow fades in as Mona the Octocat, Copilot, and Ducky dramatically fall into place next to one another while gazing optimistically into the distance.',
  },
}

import {BookIcon, PlayIcon, ShieldIcon} from '@primer/octicons-react'

const COPY = {
  title: 'Get the most out of GitHub Advanced Security',
  cards: [
    {
      icon: <ShieldIcon />,
      title: 'Maximize your defenses with industry-leading AppSec',
      description: 'Discover how our security solution can benefit your organization.',
      link: {
        label: 'Request a demo',
        href: '/security/advanced-security/demo?ref_cta=Request%20demo&ref_loc=resources_card&ref_page=%2Fadvanced_security_lp&utm_campaign=Demo_utmroutercampaign',
      },
    },
    {
      icon: <BookIcon />,
      title: 'See how improved security drives business success',
      description: 'Explore the benefits of improving software security standards in organizations.',
      link: {
        label: 'Read the Forrester Report',
        href: 'https://resources.github.com/forrester-industry-spotlight-github-advanced-security/',
      },
    },
    {
      icon: <PlayIcon />,
      title: 'How top teams secure code while moving fast',
      description: 'Learn how industry experts protect their code without sacrificing productivity.',
      link: {
        label: 'Explore videos',
        href: '/security/advanced-security/what-is-github-advanced-security',
      },
    },
  ],
} as const

export default COPY

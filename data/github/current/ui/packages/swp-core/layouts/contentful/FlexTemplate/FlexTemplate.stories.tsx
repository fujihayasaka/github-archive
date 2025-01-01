import '@primer/react-brand/lib/css/main.css'

import type {Meta, StoryObj} from '@storybook/react'

import {FlexTemplate} from './FlexTemplate'
import {BLOCKS, INLINES} from '@contentful/rich-text-types'

const meta: Meta<typeof FlexTemplate> = {
  title: 'Mkt/Swp/Contentful/FlexTemplate',
  component: FlexTemplate,
}

export default meta

type Story = StoryObj<typeof FlexTemplate>

export const Default: Story = {
  args: {
    page: {
      sys: {
        id: '2UfXY5jRH7icoMDJnmPdQT',
        contentType: {
          sys: {
            id: 'containerPage',
          },
        },
      },
      fields: {
        path: '/contentful-lp-tests/template-flex',
        settings: {
          sys: {
            id: 'GljhrODli6AFEilSnxHPA',
            contentType: {
              sys: {
                id: 'pageSettings',
              },
            },
          },
          fields: {
            colorMode: 'dark',
          },
        },
        template: {
          sys: {
            id: '1Cr3de1nTcfeUsDvJyqfBs',
            contentType: {
              sys: {
                id: 'templateFlex',
              },
            },
          },
          fields: {
            subnav: {
              sys: {
                id: '6CyXhcyLkSW9Sv8gvLqzb5',
                contentType: {
                  sys: {
                    id: 'primerComponentSubnav',
                  },
                },
              },
              fields: {
                heading: {
                  sys: {
                    id: '34l3EvQC8GKphedsmeBR5h',
                    contentType: {
                      sys: {
                        id: 'link',
                      },
                    },
                  },
                  fields: {
                    href: 'https://github.com/education',
                    text: 'Education',
                    openInNewTab: false,
                  },
                },
                links: [
                  {
                    sys: {
                      id: '7iNyp6gNnhAcpPT5iywBLh',
                      contentType: {
                        sys: {
                          id: 'link',
                        },
                      },
                    },
                    fields: {
                      href: 'https://github.com/education/students',
                      text: 'Students',
                      openInNewTab: false,
                    },
                  },
                  {
                    sys: {
                      id: 'Dif25EQ2AhJBoA6G6Pnu6',
                      contentType: {
                        sys: {
                          id: 'link',
                        },
                      },
                    },
                    fields: {
                      href: 'https://github.com/education/teachers',
                      text: 'Teachers',
                      openInNewTab: false,
                    },
                  },
                  {
                    sys: {
                      id: '4A0iHsDWgtGWwrq0QT6UIJ',
                      contentType: {
                        sys: {
                          id: 'link',
                        },
                      },
                    },
                    fields: {
                      href: 'https://github.com/education/schools',
                      text: 'Schools',
                      openInNewTab: false,
                    },
                  },
                  {
                    sys: {
                      id: '4Y9oDe6ziwmyVu8u80zZch',
                      contentType: {
                        sys: {
                          id: 'link',
                        },
                      },
                    },
                    fields: {
                      href: 'https://github.com/education/partners',
                      text: 'Partners',
                      openInNewTab: false,
                    },
                  },
                ],
              },
            },
            hero: {
              sys: {
                id: '6W6CtI32cMuL7Paxj2aOSu',
                contentType: {
                  sys: {
                    id: 'primerComponentHero',
                  },
                },
              },
              fields: {
                align: 'start',
                label: 'GitHub Education',
                heading: 'Connect and collaborate with educators and students worldwide',
                imagePosition: 'Block',
                description: 'Join us in our mission to empower the next generation of developers',
                callToActionPrimary: {
                  sys: {
                    id: '1V7oIvAQ6rtUKhomlDE4Tg',
                    contentType: {
                      sys: {
                        id: 'link',
                      },
                    },
                  },
                  fields: {
                    href: 'https://survey3.medallia.com/?IqFRAo-edu-partnership',
                    text: 'Partner with GitHub Education',
                    openInNewTab: false,
                  },
                },
              },
            },
            heroBackgroundImage: {
              sys: {
                id: '22Wfu01rB6ZJuKsz07b3UC',
                contentType: {
                  sys: {
                    id: 'backgroundImage',
                  },
                },
              },
              fields: {
                image: {
                  fields: {
                    description: 'A group of people working on laptops with abstract shapes and calendars',
                    file: {
                      url: '//images.ctfassets.net/8aevphvgewt8/131JffhVIrbXCclE3QUlYn/9e51844548d4dd7b1780d8ef651e9a47/partners.webp',
                    },
                  },
                },
                focus: 'left',
                colorMode: 'dark',
              },
            },
            sections: [
              {
                sys: {
                  id: 'RymsVkXLEo64k20UuPMOh',
                  contentType: {
                    sys: {
                      id: 'flexSection',
                    },
                  },
                },
                fields: {
                  introContent: {
                    sys: {
                      id: '3Ko5pxdUKBO5RHPtXUXxqg',
                      contentType: {
                        sys: {
                          id: 'primerComponentSectionIntro',
                        },
                      },
                    },
                    fields: {
                      align: 'center',
                      fullWidth: false,
                      heading: {
                        nodeType: BLOCKS.DOCUMENT,
                        data: {},
                        content: [
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: 'GitHub scales with teams of any size.',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                        ],
                      },
                    },
                  },
                  pillars: {
                    sys: {
                      id: '2Qr1IkMc5b1nxpXk7e6mr3',
                      contentType: {
                        sys: {
                          id: 'primerPillars',
                        },
                      },
                    },
                    fields: {
                      pillars: [
                        {
                          sys: {
                            id: '4RUP3WBgKX308H6jQ3ze4J',
                            contentType: {
                              sys: {
                                id: 'primerComponentPillar',
                              },
                            },
                          },
                          fields: {
                            align: 'start',
                            icon: 'device-mobile',
                            heading: 'Code from any device',
                            description: {
                              nodeType: BLOCKS.DOCUMENT,
                              data: {},
                              content: [
                                {
                                  nodeType: BLOCKS.PARAGRAPH,
                                  data: {},
                                  content: [
                                    {
                                      nodeType: 'text',
                                      value:
                                        'Want to code on an iPad? Go for it. Spin up Codespaces from any device with internet access. Don’t worry if your device is powerful enough—Codespaces lives in the cloud.',
                                      marks: [],
                                      data: {},
                                    },
                                  ],
                                },
                              ],
                            },
                          },
                        },
                        {
                          sys: {
                            id: '3GGAKuQtynLeJZwuVn71D1',
                            contentType: {
                              sys: {
                                id: 'primerComponentPillar',
                              },
                            },
                          },
                          fields: {
                            align: 'start',
                            icon: 'zap',
                            heading: 'Onboard at the speed of thought',
                            description: {
                              nodeType: BLOCKS.DOCUMENT,
                              data: {},
                              content: [
                                {
                                  nodeType: BLOCKS.PARAGRAPH,
                                  data: {},
                                  content: [
                                    {
                                      nodeType: 'text',
                                      value:
                                        'No more building your dev environment while you onboard. Codespaces launches instantly from any repository on GitHub with pre-configured, secure environments.',
                                      marks: [],
                                      data: {},
                                    },
                                  ],
                                },
                              ],
                            },
                          },
                        },
                        {
                          sys: {
                            id: '4WSyQmlcVFRcWDPEYcMXvV',
                            contentType: {
                              sys: {
                                id: 'primerComponentPillar',
                              },
                            },
                          },
                          fields: {
                            align: 'start',
                            icon: 'database',
                            heading: 'Streamline contractor onboarding',
                            description: {
                              nodeType: BLOCKS.DOCUMENT,
                              data: {},
                              content: [
                                {
                                  nodeType: BLOCKS.PARAGRAPH,
                                  data: {},
                                  content: [
                                    {
                                      nodeType: 'text',
                                      value:
                                        'Codespaces gives you control over how your consultants access your resources, while providing them with instant onboarding and a fluid developer experience.',
                                      marks: [],
                                      data: {},
                                    },
                                  ],
                                },
                              ],
                            },
                          },
                        },
                      ],
                    },
                  },
                  logoSuite: {
                    sys: {
                      id: 'bCB6sqfhVRwlEoDyVYA9U',
                      contentType: {
                        sys: {
                          id: 'primerComponentLogoSuite',
                        },
                      },
                    },
                    fields: {
                      heading: 'Logos for American Airlines, Shopify, EY, P&G, and Spotify',
                      visuallyHideHeading: false,
                      description: {
                        nodeType: BLOCKS.DOCUMENT,
                        data: {},
                        content: [
                          {
                            data: {},
                            content: [
                              {
                                data: {},
                                marks: [],
                                value:
                                  'Logos for American Airlines, Shopify, EY, P&G, and Spotify. Logos for American Airlines, Shopify, EY, P&G, and Spotify',
                                nodeType: 'text',
                              },
                            ],
                            nodeType: BLOCKS.PARAGRAPH,
                          },
                        ],
                      },
                      marquee: 'off',
                      hasDivider: true,
                      variant: 'emphasis',
                      align: 'center',
                      logos: ['Spotify', 'Ernst and Young', 'American Airlines', 'Procter and Gamble', '3M'],
                    },
                  },
                  cards: {
                    sys: {
                      id: '24BqUDBIIIt1j8kBRZrqjP',
                      contentType: {
                        sys: {
                          id: 'primerCards',
                        },
                      },
                    },
                    fields: {
                      cards: [
                        {
                          sys: {
                            id: '3GWMXc4NyoTtWo6FPP41w',
                            contentType: {
                              sys: {
                                id: 'primerComponentCard',
                              },
                            },
                          },
                          fields: {
                            href: '#',
                            heading: 'Contribution activity',
                            description: {
                              nodeType: BLOCKS.DOCUMENT,
                              data: {},
                              content: [
                                {
                                  data: {},
                                  content: [
                                    {
                                      data: {},
                                      marks: [],
                                      value: 'Count of total contribution activity to Discussions, Issues, and PRs.',
                                      nodeType: 'text',
                                    },
                                  ],
                                  nodeType: BLOCKS.PARAGRAPH,
                                },
                              ],
                            },
                            iconColor: 'default',
                            iconBackground: false,
                            variant: 'default',
                            image: {
                              fields: {
                                description: '',
                                file: {
                                  url: '//images.ctfassets.net/8aevphvgewt8/11IhnjHmTANNqphbQJgcL5/fa7995995926871a41afa7984b0c4251/statement-1.webp',
                                },
                              },
                            },
                          },
                        },
                        {
                          sys: {
                            id: '3jlYdyD8XbU8MflwWpGkFb',
                            contentType: {
                              sys: {
                                id: 'primerComponentCard',
                              },
                            },
                          },
                          fields: {
                            href: '#',
                            heading: 'Discussions page views',
                            description: {
                              nodeType: BLOCKS.DOCUMENT,
                              data: {},
                              content: [
                                {
                                  nodeType: BLOCKS.PARAGRAPH,
                                  data: {},
                                  content: [
                                    {
                                      nodeType: 'text',
                                      value:
                                        'Total page views to Discussions segmented by logged in vs anonymous users.',
                                      marks: [],
                                      data: {},
                                    },
                                  ],
                                },
                                {
                                  nodeType: BLOCKS.PARAGRAPH,
                                  data: {},
                                  content: [
                                    {
                                      nodeType: 'text',
                                      value: '\n',
                                      marks: [],
                                      data: {},
                                    },
                                  ],
                                },
                              ],
                            },
                            iconColor: 'default',
                            iconBackground: false,
                            variant: 'default',
                            image: {
                              fields: {
                                description: '',
                                file: {
                                  url: '//images.ctfassets.net/8aevphvgewt8/7y4dgTYTcVLvcCl5cZyD23/51ce57bdeef368203be6e022ea196922/statement-2.webp',
                                },
                              },
                            },
                          },
                        },
                        {
                          sys: {
                            id: '6XMYLw50sZ8ubDerjYk4CV',
                            contentType: {
                              sys: {
                                id: 'primerComponentCard',
                              },
                            },
                          },
                          fields: {
                            href: '#',
                            heading: 'Discussions daily contributors',
                            description: {
                              nodeType: BLOCKS.DOCUMENT,
                              data: {},
                              content: [
                                {
                                  data: {},
                                  content: [
                                    {
                                      data: {},
                                      marks: [],
                                      value:
                                        'Count of unique users who have reacted, upvoted, marked an answer, commented, or posted in the selected period.',
                                      nodeType: 'text',
                                    },
                                  ],
                                  nodeType: BLOCKS.PARAGRAPH,
                                },
                                {
                                  data: {},
                                  content: [
                                    {
                                      data: {},
                                      marks: [],
                                      value: '\n',
                                      nodeType: 'text',
                                    },
                                  ],
                                  nodeType: BLOCKS.PARAGRAPH,
                                },
                              ],
                            },
                            iconColor: 'default',
                            iconBackground: false,
                            variant: 'default',
                            image: {
                              fields: {
                                description: '',
                                file: {
                                  url: '//images.ctfassets.net/8aevphvgewt8/4qEfo418uIA9zPhpYGYRJw/d34183f9ce60563bd73961bdfa579181/statement-3.webp',
                                },
                              },
                            },
                          },
                        },
                      ],
                    },
                  },
                  featuredBento: {
                    sys: {
                      id: '6fy0laNzyP9w7QA6CZ1wa9',
                      contentType: {
                        sys: {
                          id: 'featuredBento',
                        },
                      },
                    },
                    fields: {
                      title: '/solutions Bento',
                      heading: {
                        nodeType: BLOCKS.DOCUMENT,
                        data: {},
                        content: [
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: 'The enterprise-grade platform that developers know and love.',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                        ],
                      },
                      link: {
                        sys: {
                          id: '2k9tHlG29BEP8ByVe5ypyO',
                          contentType: {
                            sys: {
                              id: 'link',
                            },
                          },
                        },
                        fields: {
                          href: 'https://github.com/enterprise',
                          text: 'Learn more about GitHub Enterprise',
                          openInNewTab: false,
                        },
                      },
                      icon: 'globe',
                      iconColor: 'purple',
                      image: {
                        fields: {
                          description: 'Stack with GitHub logo on the top layer',
                          file: {
                            url: '//images.ctfassets.net/8aevphvgewt8/29CiGKTG31W7VVxW3MXimT/cfdab99c54f2dd057746274707fa05c9/Stack-GitHub-logo.webp',
                          },
                        },
                      },
                    },
                  },
                  prose: {
                    sys: {
                      id: '6qNimJgkJlLZP0vESbR3eE',
                      contentType: {
                        sys: {
                          id: 'primerComponentProse',
                        },
                      },
                    },
                    fields: {
                      text: {
                        nodeType: BLOCKS.DOCUMENT,
                        data: {},
                        content: [
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: 'September 24, 2024 - San Francisco, CA - ',
                                marks: [],
                                data: {},
                              },
                              {
                                nodeType: INLINES.HYPERLINK,
                                data: {
                                  uri: 'https://github.com/about',
                                },
                                content: [
                                  {
                                    nodeType: 'text',
                                    value: 'GitHub',
                                    marks: [],
                                    data: {},
                                  },
                                ],
                              },
                              {
                                nodeType: 'text',
                                value:
                                  ', the most widely adopted Copilot-powered developer platform, announced GitHub Enterprise Cloud will offer a robust data residency feature for enterprises, starting with general availability in the European Union (EU) on October 29, 2024. GitHub also confirms that additional regions are coming next, including Australia, Asia, and Latin America. With improved enterprise-grade features and more control over where code is stored, GitHub Enterprise Cloud will help more enterprise customers meet their security and compliance needs with data residency that addresses:',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.UL_LIST,
                            data: {},
                            content: [
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value:
                                          'The ability to store your code and repository data in your preferred region',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value:
                                          'Enhanced user control, allowing organizations to manage and control user accounts',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value:
                                          'Unique namespaces specific to your company on ghe.com isolated from the open source cloud',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value:
                                          'Enhanced availability and support for zone-based business continuity and disaster recovery',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  '"In light of the mounting importance of data residency needs, there is a clear desire for organizations to have more control over where their most valuable asset, their code, is stored. GitHub recognizes this pressing need, and on October 29, we will offer the ability for all organizations to store their code in the EU," said GitHub CEO Thomas Dohmke. "The timing is crucial as organizations in the EU and across the world are racing to empower their software developers with AI at every step to get ahead and win in the global market. With the data residency feature of GitHub Enterprise Cloud, we will enable every organization in the EU with the data governance they need to embark on their AI transformation journey with our end-to-end, Copilot-powered developer platform. By doing so, we aim to accelerate digital transformation and economic growth in the EU and across the planet."',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.HEADING_2,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: 'Accelerating enterprises through a Copilot-powered developer experience\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  'By 2027, the number of platform engineering teams using AI to augment every phase of the software development life cycle (SDLC) will increase from 5% to 40%, according to the ',
                                marks: [],
                                data: {},
                              },
                              {
                                nodeType: INLINES.HYPERLINK,
                                data: {
                                  uri: 'https://www.gartner.com/en/documents/5682355',
                                },
                                content: [
                                  {
                                    nodeType: 'text',
                                    value: 'Gartner® Magic Quadrant™ for AI Code Assistants',
                                    marks: [],
                                    data: {},
                                  },
                                ],
                              },
                              {
                                nodeType: 'text',
                                value:
                                  '. As organizations continue to embrace AI in the cloud to offer developers greater abstraction, automation, and flexibility across the software development lifecycle, GitHub Enterprise Cloud is designed to offer enterprises innovation without dealing with the complexities of performance, infrastructure, and availability. By providing GitHub Enterprise Cloud with data residency, GitHub is offering its customers to not just choose where their code lives, but to also choose a partner that understands the importance of safeguarding critical assets with reliable and secure infrastructure. ',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  'We’re already hearing from enterprises about the benefits they’re seeing from this next version of GitHub Enterprise Cloud:',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.UL_LIST,
                            data: {},
                            content: [
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value:
                                          '"Implementing GitHub Enterprise Cloud with its data residency capability for the EU has been a game-changer for ZEISS. It not only aligns with local EU data protection regulations but also enhances our developer productivity and experience by providing the rich feature set of GitHub Enterprise Cloud." - Henrik Boettcher, Tech Lead, Development Platforms at ZEISS',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value:
                                          '"As a Volkswagen Group company, ensuring that our data is predominantly hosted in Europe is a top priority for CARIAD. By bringing data residency to GitHub Enterprise Cloud, we now have a valuable solution that aligns with our needs, marking a crucial first step in our plan to reduce our self-hosting efforts and empower our developers to build, deploy, and collaborate from the cloud as well. This feature is poised to become one of the most significant enhancements for us in GitHub\'s portfolio." - Alexander Hanl, Product Manager for CI/CD environment, CARIAD, a Volkswagen company',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  'By bringing data residency to GitHub Enterprise Cloud, GitHub is enabling innovation and accelerated speed to value for customers like never before. Earlier this year, GitHub introduced ',
                                marks: [],
                                data: {},
                              },
                              {
                                nodeType: INLINES.HYPERLINK,
                                data: {
                                  uri: 'https://github.blog/news-insights/product-news/github-copilot-enterprise-is-now-generally-available/',
                                },
                                content: [
                                  {
                                    nodeType: 'text',
                                    value: 'GitHub Copilot Enterprise',
                                    marks: [],
                                    data: {},
                                  },
                                ],
                              },
                              {
                                nodeType: 'text',
                                value:
                                  ' so organizations of any size can leverage the full power of generative AI across their software development workflows with integrated DevOps features like GitHub Actions, Issues, Repositories, and Pull Requests. GitHub also launched a ',
                                marks: [],
                                data: {},
                              },
                              {
                                nodeType: INLINES.HYPERLINK,
                                data: {
                                  uri: 'https://resources.github.com/metered-billing/',
                                },
                                content: [
                                  {
                                    nodeType: 'text',
                                    value: 'frictionless, cost-effective transaction experience',
                                    marks: [],
                                    data: {},
                                  },
                                ],
                              },
                              {
                                nodeType: 'text',
                                value: ' for customers to seamlessly scale on GitHub and only pay for what they use. ',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  '\n"Enterprises all over the world have growing concerns about where their data is hosted, whether that’s for performance reasons, to ensure compliance or other preferences," said Stephen O’Grady, Principal Analyst with RedMonk. "GitHub Enterprise’s new data residency capabilities were built to offer customers granular control over where their data resides and what can be done with it."',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.HEADING_2,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: 'Explore GitHub Enterprise Cloud\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  'GitHub Enterprise Cloud offers a robust platform designed to enhance productivity, collaboration, and agility in software development, while empowering customers with greater control over their data.',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  'Historically, customers seeking more control over their data have turned to GitHub Enterprise Server for self-hosting to maintain control. Now, with the upcoming availability of EU data residency in GitHub Enterprise Cloud, customers will be able to designate a storage location for their data, as well as access to the breadth and capabilities that our cloud solution enables.',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  'GitHub Enterprise Cloud operates on Microsoft Azure, a powerful and secure enterprise-grade cloud platform trusted by over 95% of Fortune 500 companies. Azure is secure by design and secure by default with built-in resiliency features for high-availability advanced encryption, and has security controls integrated into the hardware and firmware components. GitHub Enterprise Cloud leverages this functionality so that code is not only stored in the region a customer chooses, but is also protected by high standards around security and operational excellence. ',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  'To help customers interested with a transition, migration tools are available for moving from GitHub Enterprise Server or other source code management tools to GitHub Enterprise Cloud. New and existing customers can leverage GitHub Enterprise Importer, GitHub Expert Services, third-party migration tools, or partner engagements to migrate their repositories. ',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  'Beginning October 29, 2024, new and existing GitHub customers in the EU will be able to access the data residency feature of GitHub Enterprise Cloud, with availability expanding to regions including Australia, Asia, and Latin America coming next. This offering will be available only to customers with a dedicated GitHub or Microsoft account representative at this time. ',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '\n',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: '',
                                marks: [],
                                data: {},
                              },
                              {
                                nodeType: INLINES.HYPERLINK,
                                data: {
                                  uri: 'https://www.gartner.com/en/documents/5682355',
                                },
                                content: [
                                  {
                                    nodeType: 'text',
                                    value: 'Gartner, Magic Quadrant for AI Code Assistants',
                                    marks: [
                                      {
                                        type: 'italic',
                                      },
                                    ],
                                    data: {},
                                  },
                                ],
                              },
                              {
                                nodeType: 'text',
                                value:
                                  ', By Arun Batchu, Philip Walsh, Matt Brasier, Haritha Khandabattu, 19 August 2024. GARTNER is a registered trademark and service mark of Gartner, Inc. and/or its affiliates in the U.S. and internationally, Magic Quadrant is a registered trademark of Gartner, Inc. and/or its affiliates and is used herein with permission. All rights reserved.',
                                marks: [
                                  {
                                    type: 'italic',
                                  },
                                ],
                                data: {},
                              },
                            ],
                          },
                        ],
                      },
                    },
                  },
                  rivers: [
                    {
                      sys: {
                        id: '3sMpZ8i2LNWllmdih7Sgmb',
                        contentType: {
                          sys: {
                            id: 'primerComponentRiver',
                          },
                        },
                      },
                      fields: {
                        align: 'start',
                        imageTextRatio: '50:50',
                        heading: 'Secure Package Registry for Code and Workflows',
                        text: {
                          nodeType: BLOCKS.DOCUMENT,
                          data: {},
                          content: [
                            {
                              data: {},
                              content: [
                                {
                                  data: {},
                                  marks: [],
                                  value:
                                    'Securely store and manage your code and packages with GitHub credentials, integrated into your workflows via APIs and webhooks. Enjoy fast, reliable downloads through a global CDN for optimized performance.',
                                  nodeType: 'text',
                                },
                              ],
                              nodeType: BLOCKS.PARAGRAPH,
                            },
                            {
                              data: {},
                              content: [
                                {
                                  data: {},
                                  marks: [],
                                  value: '',
                                  nodeType: 'text',
                                },
                              ],
                              nodeType: BLOCKS.PARAGRAPH,
                            },
                          ],
                        },
                        callToAction: {
                          sys: {
                            id: 'fHifS5NvXtJS8b04alkjA',
                            contentType: {
                              sys: {
                                id: 'link',
                              },
                            },
                          },
                          fields: {
                            href: 'https://docs.github.com/packages',
                            text: 'Read the docs',
                            openInNewTab: false,
                          },
                        },
                        image: {
                          fields: {
                            description: '',
                            file: {
                              url: '//images.ctfassets.net/8aevphvgewt8/2nDndCZUe4d4pX9YAmJYlS/b6b6b59a1f53e18ae160434797661560/features-river-2-1.webp',
                            },
                          },
                        },
                        hasShadow: false,
                      },
                    },
                    {
                      sys: {
                        id: '6Oi5ofrqVefUzXI2sxZu0j',
                        contentType: {
                          sys: {
                            id: 'primerComponentRiverBreakout',
                          },
                        },
                      },
                      fields: {
                        a11yHeading: 'Get inspired',
                        text: {
                          nodeType: BLOCKS.DOCUMENT,
                          data: {},
                          content: [
                            {
                              data: {},
                              content: [
                                {
                                  data: {},
                                  marks: [
                                    {
                                      type: 'bold',
                                    },
                                  ],
                                  value: 'Get inspired.',
                                  nodeType: 'text',
                                },
                                {
                                  data: {},
                                  marks: [],
                                  value: ' ',
                                  nodeType: 'text',
                                },
                                {
                                  data: {},
                                  marks: [],
                                  value: 'See how your favorite communities are using discussions',
                                  nodeType: 'text',
                                },
                              ],
                              nodeType: BLOCKS.PARAGRAPH,
                            },
                          ],
                        },
                        callToAction: {
                          sys: {
                            id: '02r02rdJjmbcpOPHsGVdb',
                            contentType: {
                              sys: {
                                id: 'link',
                              },
                            },
                          },
                          fields: {
                            href: 'github.com',
                            text: 'Link Text',
                            openInNewTab: false,
                          },
                        },
                        image: {
                          fields: {
                            description: '',
                            file: {
                              url: '//images.ctfassets.net/8aevphvgewt8/125dSzdJGDINm240HXqmJ9/947f5a2aa885147ce498efcb3efac684/Screenshot_2024-09-26_at_3.37.47_PM.png',
                            },
                          },
                        },
                        hasShadow: false,
                      },
                    },
                    {
                      sys: {
                        id: '2fADfNGTk9dzSHvZ4znJF8',
                        contentType: {
                          sys: {
                            id: 'primerComponentRiver',
                          },
                        },
                      },
                      fields: {
                        align: 'end',
                        imageTextRatio: '50:50',
                        heading: 'Foobar river heading ',
                        text: {
                          nodeType: BLOCKS.DOCUMENT,
                          data: {},
                          content: [
                            {
                              data: {},
                              content: [
                                {
                                  data: {},
                                  marks: [],
                                  value:
                                    'Give your open ended conversations the room they need outside of issues. Convert discussions into issues when you’re ready to scope out work.',
                                  nodeType: 'text',
                                },
                              ],
                              nodeType: BLOCKS.PARAGRAPH,
                            },
                          ],
                        },
                        image: {
                          fields: {
                            description: '',
                            file: {
                              url: '//images.ctfassets.net/8aevphvgewt8/NPuKmt3jdmhBD0rPB44Q9/a212b755b8e4f81e3df0cc62376d5d86/features-river-5.webp',
                            },
                          },
                        },
                        hasShadow: false,
                      },
                    },
                    {
                      sys: {
                        id: '6fFYWQBfNFeK2MBbyWtqAJ',
                        contentType: {
                          sys: {
                            id: 'primerComponentRiver',
                          },
                        },
                      },
                      fields: {
                        align: 'center',
                        imageTextRatio: '50:50',
                        heading: 'Get inspired',
                        text: {
                          nodeType: BLOCKS.DOCUMENT,
                          data: {},
                          content: [
                            {
                              data: {},
                              content: [
                                {
                                  data: {},
                                  marks: [],
                                  value: 'See how your favorite communities are using discussions',
                                  nodeType: 'text',
                                },
                              ],
                              nodeType: BLOCKS.PARAGRAPH,
                            },
                            {
                              data: {},
                              content: [
                                {
                                  data: {},
                                  marks: [],
                                  value: '\n',
                                  nodeType: 'text',
                                },
                              ],
                              nodeType: BLOCKS.PARAGRAPH,
                            },
                          ],
                        },
                        image: {
                          fields: {
                            description: '',
                            file: {
                              url: '//images.ctfassets.net/8aevphvgewt8/125dSzdJGDINm240HXqmJ9/947f5a2aa885147ce498efcb3efac684/Screenshot_2024-09-26_at_3.37.47_PM.png',
                            },
                          },
                        },
                        hasShadow: false,
                      },
                    },
                  ],
                  testimonials: [
                    {
                      sys: {
                        id: '23kYC5GBD05KjltbpPsYHT',
                        contentType: {
                          sys: {
                            id: 'primerComponentTestimonial',
                          },
                        },
                      },
                      fields: {
                        quote: {
                          nodeType: BLOCKS.DOCUMENT,
                          data: {},
                          content: [
                            {
                              data: {},
                              content: [
                                {
                                  data: {},
                                  marks: [],
                                  value:
                                    'The availability of out-of-the-box integrations with our existing tooling is a big part of GitHub’s appeal. GitHub really helps bring DevOps to life.',
                                  nodeType: 'text',
                                },
                              ],
                              nodeType: BLOCKS.PARAGRAPH,
                            },
                          ],
                        },
                        size: 'large',
                        author: {
                          sys: {
                            id: '740SAjN4JjiFpULc6XYAqp',
                            contentType: {
                              sys: {
                                id: 'person',
                              },
                            },
                          },
                          fields: {
                            fullName: 'Danilo Suntal',
                            position: 'Manufacturing Data Flow Product and Platform, P&G',
                            photo: {
                              fields: {
                                description: 'Danilo Suntal avatar',
                                file: {
                                  url: '//images.ctfassets.net/8aevphvgewt8/2Z3Y0NdYm0a1mwA1iZ3e9X/d8624c8feaaaca6fad77717917120cb7/1517546627497.jpg',
                                },
                              },
                            },
                          },
                        },
                        displayedAuthorImage: 'logo',
                        logo: {
                          fields: {
                            description: 'Procter & Gamble logo',
                            file: {
                              url: '//images.ctfassets.net/8aevphvgewt8/5oaZjAaI1QbQjPWOacd4Mp/80b3e0d78d6908f6836f6e116f7a363c/Procter___Gamble_logo.webp',
                            },
                          },
                        },
                      },
                    },
                  ],
                  statistics: {
                    sys: {
                      id: '5o6a6ofl6Uqel2JxCfgIob',
                      contentType: {
                        sys: {
                          id: 'primerStatistics',
                        },
                      },
                    },
                    fields: {
                      statistics: [
                        {
                          sys: {
                            id: '1j500ScsIqFFqyjFPbVrVz',
                            contentType: {
                              sys: {
                                id: 'primerComponentStatistic',
                              },
                            },
                          },
                          fields: {
                            heading: '75%',
                            size: 'medium',
                            variant: 'boxed',
                            description: 'reduced time spent managing tools',
                            descriptionVariant: 'default',
                          },
                        },
                        {
                          sys: {
                            id: '3xYCCkxqsxG5s816ZQUVW5',
                            contentType: {
                              sys: {
                                id: 'primerComponentStatistic',
                              },
                            },
                          },
                          fields: {
                            heading: '433%',
                            size: 'medium',
                            variant: 'boxed',
                            description: 'ROI with GitHub Enterprise',
                            descriptionVariant: 'default',
                          },
                        },
                        {
                          sys: {
                            id: '5ge48ERp3A1aGJx89NODQC',
                            contentType: {
                              sys: {
                                id: 'primerComponentStatistic',
                              },
                            },
                          },
                          fields: {
                            heading: '77,000',
                            size: 'medium',
                            variant: 'boxed',
                            description: 'organizations using GitHub Copilot',
                            descriptionVariant: 'default',
                          },
                        },
                        {
                          sys: {
                            id: '3xYCCkxqsxG5s816ZQUVW5',
                            contentType: {
                              sys: {
                                id: 'primerComponentStatistic',
                              },
                            },
                          },
                          fields: {
                            heading: '433%',
                            size: 'medium',
                            variant: 'boxed',
                            description: 'ROI with GitHub Enterprise',
                            descriptionVariant: 'default',
                          },
                        },
                      ],
                    },
                  },
                  visualSettings: {
                    sys: {
                      id: '6k5PlUHTZ8rkkCrrJzt72B',
                      contentType: {
                        sys: {
                          id: 'flexSectionVisualSettings',
                        },
                      },
                    },
                    fields: {
                      paddingBlockStart: 'spacious',
                      paddingBlockEnd: 'spacious',
                      backgroundColor: 'subtle',
                      backgroundImagePosition: 'center',
                      backgroundImageSize: 'contain',
                      roundedCorners: true,
                      verticalGap: 'normal',
                    },
                  },
                },
              },
              {
                sys: {
                  id: '2PpCAJxypQtU8OkrudFh8c',
                  contentType: {
                    sys: {
                      id: 'flexSection',
                    },
                  },
                },
                fields: {
                  id: 'baz',
                  introContent: {
                    sys: {
                      id: '1BP2TwWwGPGqK03NlP5xDv',
                      contentType: {
                        sys: {
                          id: 'introStackedItems',
                        },
                      },
                    },
                    fields: {
                      headline: 'A single, integrated, enterprise-ready platform',
                      items: [
                        {
                          sys: {
                            id: 'rcL4B36IAmflyqwcfgoEt',
                            contentType: {
                              sys: {
                                id: 'introItem',
                              },
                            },
                          },
                          fields: {
                            text: {
                              nodeType: BLOCKS.DOCUMENT,
                              data: {},
                              content: [
                                {
                                  data: {},
                                  content: [
                                    {
                                      data: {},
                                      marks: [
                                        {
                                          type: 'bold',
                                        },
                                      ],
                                      value:
                                        'Build secure healthcare solutions in a single, integrated, enterprise-ready platform',
                                      nodeType: 'text',
                                    },
                                    {
                                      data: {},
                                      marks: [],
                                      value: ' that keeps developers in their productivity-and-comfort zone.',
                                      nodeType: 'text',
                                    },
                                  ],
                                  nodeType: BLOCKS.PARAGRAPH,
                                },
                              ],
                            },
                          },
                        },
                        {
                          sys: {
                            id: 'rcL4B36IAmflyqwcfgoEt',
                            contentType: {
                              sys: {
                                id: 'introItem',
                              },
                            },
                          },
                          fields: {
                            text: {
                              nodeType: BLOCKS.DOCUMENT,
                              data: {},
                              content: [
                                {
                                  data: {},
                                  content: [
                                    {
                                      data: {},
                                      marks: [
                                        {
                                          type: 'bold',
                                        },
                                      ],
                                      value:
                                        'Build secure healthcare solutions in a single, integrated, enterprise-ready platform',
                                      nodeType: 'text',
                                    },
                                    {
                                      data: {},
                                      marks: [],
                                      value: ' that keeps developers in their productivity-and-comfort zone.',
                                      nodeType: 'text',
                                    },
                                  ],
                                  nodeType: BLOCKS.PARAGRAPH,
                                },
                              ],
                            },
                          },
                        },
                        {
                          sys: {
                            id: 'rcL4B36IAmflyqwcfgoEt',
                            contentType: {
                              sys: {
                                id: 'introItem',
                              },
                            },
                          },
                          fields: {
                            text: {
                              nodeType: BLOCKS.DOCUMENT,
                              data: {},
                              content: [
                                {
                                  data: {},
                                  content: [
                                    {
                                      data: {},
                                      marks: [
                                        {
                                          type: 'bold',
                                        },
                                      ],
                                      value:
                                        'Build secure healthcare solutions in a single, integrated, enterprise-ready platform',
                                      nodeType: 'text',
                                    },
                                    {
                                      data: {},
                                      marks: [],
                                      value: ' that keeps developers in their productivity-and-comfort zone.',
                                      nodeType: 'text',
                                    },
                                  ],
                                  nodeType: BLOCKS.PARAGRAPH,
                                },
                              ],
                            },
                          },
                        },
                      ],
                      link: {
                        sys: {
                          id: '2k9tHlG29BEP8ByVe5ypyO',
                          contentType: {
                            sys: {
                              id: 'link',
                            },
                          },
                        },
                        fields: {
                          href: 'https://github.com/enterprise',
                          text: 'Learn more about GitHub Enterprise',
                          openInNewTab: false,
                        },
                      },
                    },
                  },
                  pillars: {
                    sys: {
                      id: '7DploUag3gQGx07mgPGUpf',
                      contentType: {
                        sys: {
                          id: 'primerPillars',
                        },
                      },
                    },
                    fields: {
                      pillars: [
                        {
                          sys: {
                            id: '5piPmC3TGuYvqj5IV6ZO4h',
                            contentType: {
                              sys: {
                                id: 'primerComponentPillar',
                              },
                            },
                          },
                          fields: {
                            align: 'start',
                            icon: 'diamond',
                            heading: 'Programming and Visibility',
                            description: {
                              nodeType: BLOCKS.DOCUMENT,
                              data: {},
                              content: [
                                {
                                  nodeType: BLOCKS.PARAGRAPH,
                                  data: {},
                                  content: [
                                    {
                                      nodeType: 'text',
                                      value:
                                        'Participants engage in a 10-week peer-based cohort program that includes instruction, workshops, and expert speakers. Participants will have the opportunity to amplify through GitHub channels, events and showcases.',
                                      marks: [],
                                      data: {},
                                    },
                                  ],
                                },
                              ],
                            },
                          },
                        },
                        {
                          sys: {
                            id: '2ULM4wSJNpBD3THFE2Mjxe',
                            contentType: {
                              sys: {
                                id: 'primerComponentPillar',
                              },
                            },
                          },
                          fields: {
                            align: 'start',
                            icon: 'heart',
                            heading: 'Collaboration and Community',
                            description: {
                              nodeType: BLOCKS.DOCUMENT,
                              data: {},
                              content: [
                                {
                                  nodeType: BLOCKS.PARAGRAPH,
                                  data: {},
                                  content: [
                                    {
                                      nodeType: 'text',
                                      value:
                                        'Participants will have a diverse community of builders to learn from within the cohort to exchange ideas, build partnerships, and accelerate project growth and adoption.',
                                      marks: [],
                                      data: {},
                                    },
                                  ],
                                },
                                {
                                  nodeType: BLOCKS.PARAGRAPH,
                                  data: {},
                                  content: [
                                    {
                                      nodeType: 'text',
                                      value: '',
                                      marks: [],
                                      data: {},
                                    },
                                  ],
                                },
                              ],
                            },
                          },
                        },
                        {
                          sys: {
                            id: '5wWcRozHfyT3qwBiBTrMrJ',
                            contentType: {
                              sys: {
                                id: 'primerComponentPillar',
                              },
                            },
                          },
                          fields: {
                            align: 'start',
                            icon: 'comment-discussion',
                            heading: 'Mentorship and Support',
                            description: {
                              nodeType: BLOCKS.DOCUMENT,
                              data: {},
                              content: [
                                {
                                  nodeType: BLOCKS.PARAGRAPH,
                                  data: {},
                                  content: [
                                    {
                                      nodeType: 'text',
                                      value:
                                        'The program will offer mentorship from community and Hubbers in fields of open source, AI, Security as well as topical areas like fundraising and business.',
                                      marks: [],
                                      data: {},
                                    },
                                  ],
                                },
                                {
                                  nodeType: BLOCKS.PARAGRAPH,
                                  data: {},
                                  content: [
                                    {
                                      nodeType: 'text',
                                      value: '',
                                      marks: [],
                                      data: {},
                                    },
                                  ],
                                },
                              ],
                            },
                          },
                        },
                      ],
                    },
                  },
                  logoSuite: {
                    sys: {
                      id: 'NPYdZcTzWuKM8gBXIBNYI',
                      contentType: {
                        sys: {
                          id: 'primerComponentLogoSuite',
                        },
                      },
                    },
                    fields: {
                      heading: 'GitHub partners with industry leaders',
                      visuallyHideHeading: true,
                      marquee: 'off',
                      hasDivider: false,
                      variant: 'muted',
                      align: 'center',
                      logos: ['Philips'],
                    },
                  },
                  cards: {
                    sys: {
                      id: 'RhnZXtHI1cq105oLbtwXj',
                      contentType: {
                        sys: {
                          id: 'primerCards',
                        },
                      },
                    },
                    fields: {
                      cards: [
                        {
                          sys: {
                            id: '2yTfoiemCHzyXtF26yhxtY',
                            contentType: {
                              sys: {
                                id: 'primerComponentCard',
                              },
                            },
                          },
                          fields: {
                            href: '#',
                            heading: 'GitHub CLI',
                            description: {
                              nodeType: BLOCKS.DOCUMENT,
                              data: {},
                              content: [
                                {
                                  data: {},
                                  content: [
                                    {
                                      data: {},
                                      marks: [],
                                      value: 'View, update, and create issues without ever leaving your terminal.',
                                      nodeType: 'text',
                                    },
                                  ],
                                  nodeType: BLOCKS.PARAGRAPH,
                                },
                              ],
                            },
                            iconColor: 'default',
                            iconBackground: false,
                          },
                        },
                        {
                          sys: {
                            id: '2yTfoiemCHzyXtF26yhxtY',
                            contentType: {
                              sys: {
                                id: 'primerComponentCard',
                              },
                            },
                          },
                          fields: {
                            href: '#',
                            heading: 'GitHub CLI',
                            description: {
                              nodeType: BLOCKS.DOCUMENT,
                              data: {},
                              content: [
                                {
                                  data: {},
                                  content: [
                                    {
                                      data: {},
                                      marks: [],
                                      value: 'View, update, and create issues without ever leaving your terminal.',
                                      nodeType: 'text',
                                    },
                                  ],
                                  nodeType: BLOCKS.PARAGRAPH,
                                },
                              ],
                            },
                            iconColor: 'default',
                            iconBackground: false,
                          },
                        },
                      ],
                    },
                  },
                  featuredBento: {
                    sys: {
                      id: 'SDgQgLzkxBEdKDjZHEXVv',
                      contentType: {
                        sys: {
                          id: 'featuredBento',
                        },
                      },
                    },
                    fields: {
                      title: '/solutions/industry/financial-services Bento',
                      heading: {
                        nodeType: BLOCKS.DOCUMENT,
                        data: {},
                        content: [
                          {
                            data: {},
                            content: [
                              {
                                data: {},
                                marks: [],
                                value:
                                  'Read how Societe Generale tripled their releases and cut development time by more than half.',
                                nodeType: 'text',
                              },
                            ],
                            nodeType: BLOCKS.PARAGRAPH,
                          },
                        ],
                      },
                      link: {
                        sys: {
                          id: '6SH9854eyo9As3nFAXKpZr',
                          contentType: {
                            sys: {
                              id: 'link',
                            },
                          },
                        },
                        fields: {
                          href: 'https://github.com/customer-stories/societe-generale',
                          text: 'Read the customer story',
                          openInNewTab: false,
                        },
                      },
                      icon: 'briefcase',
                      iconColor: 'purple',
                      image: {
                        fields: {
                          description: '',
                          file: {
                            url: '//images.ctfassets.net/8aevphvgewt8/Yb7bDbf9PXFoD31AnPGvv/beebe4e2adae829de300a764a232f3bc/sg-hero.avif',
                          },
                        },
                      },
                    },
                  },
                  prose: {
                    sys: {
                      id: '7mnKj5qgO7rbE7QDhXucLy',
                      contentType: {
                        sys: {
                          id: 'primerComponentProse',
                        },
                      },
                    },
                    fields: {
                      text: {
                        nodeType: BLOCKS.DOCUMENT,
                        data: {},
                        content: [
                          {
                            nodeType: BLOCKS.HEADING_2,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: 'Why is DAST important for application security?',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  'Although billions of dollars have been invested into AppSec tools, 85% of applications still contain known vulnerabilities, with most breaches occurring at the application layer, according to the GitHub software security guide.',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: 'DAST tools are a type of security tool that can be used as part of an ',
                                marks: [],
                                data: {},
                              },
                              {
                                nodeType: INLINES.HYPERLINK,
                                data: {
                                  uri: 'https://resources.github.com/security/what-is-application-security/',
                                },
                                content: [
                                  {
                                    nodeType: 'text',
                                    value: 'application security program',
                                    marks: [],
                                    data: {},
                                  },
                                ],
                              },
                              {
                                nodeType: 'text',
                                value: '. DAST assists developers during the software development lifecycle (',
                                marks: [],
                                data: {},
                              },
                              {
                                nodeType: INLINES.HYPERLINK,
                                data: {
                                  uri: 'https://github.com/resources/articles/software-development/what-is-sdlc',
                                },
                                content: [
                                  {
                                    nodeType: 'text',
                                    value: 'SDLC',
                                    marks: [],
                                    data: {},
                                  },
                                ],
                              },
                              {
                                nodeType: 'text',
                                value:
                                  ') by helping them catch vulnerabilities that can be exploited by malicious attacks. Vulnerabilities can range from simple coding errors to more complex issues such as insecure settings or misconfigured environments. Identifying vulnerabilities early on helps businesses protect against data breaches, tarnished brand reputations, and lost customer trust.',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.HEADING_2,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: 'How do DAST tools work?',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  'DAST tools empower development teams to look at the application from a black-box security perspective, which is very close to the attacker mindset. DAST mimics the same techniques that malicious attackers—who don’t know the application’s infrastructure, architecture, or code—use to find ',
                                marks: [],
                                data: {},
                              },
                              {
                                nodeType: INLINES.HYPERLINK,
                                data: {
                                  uri: 'https://github.com/resources/articles/security/what-is-vulnerability-scanning',
                                },
                                content: [
                                  {
                                    nodeType: 'text',
                                    value: 'application vulnerabilities',
                                    marks: [],
                                    data: {},
                                  },
                                ],
                              },
                              {
                                nodeType: 'text',
                                value: '. The DAST tool:',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.UL_LIST,
                            data: {},
                            content: [
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value:
                                          'Performs a crawl to pick up on application layer attack points like links, cookies, and URL parameters.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value: 'Creates a map of the web applications’ pages and issues.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value:
                                          'Audits what it discovered and simulates different kinds of malicious attacks to uncover security vulnerabilities.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value:
                                          'Alerts the development team when it finds a vulnerability in an application.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.HEADING_2,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: 'Types of DAST',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  'There are two types of dynamic application security testing. Automated DAST, described in the bullet points above, uses software to scan the application for vulnerabilities and replicate the attacks. For more complex situations, security experts use manual DAST procedures to test for vulnerabilities that automated DAST might miss. To combat sophisticated hackers, development teams might use a combination of both automated and manual DAST.',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  'Although automated DAST is typically faster and more efficient, it might not be able to identify all vulnerabilities in a web application and may generate false positives. Manual DAST tends to be more accurate because it can be tailored to the web application, but it’s more time consuming and resource intensive.',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.HEADING_2,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: 'Benefits of DAST',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  'Also known as a web application vulnerability scanner, DAST scanning helps application development teams safeguard their web applications from the most damaging attacks, including ones that give hackers access to sensitive data such as credit cards and customer information.',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  'Dynamic application security testing is an effective tool for identifying externally visible security issues and runtime problems that make it possible for hackers to carry out the following web application attacks:',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.UL_LIST,
                            data: {},
                            content: [
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value: 'SQL injection',
                                        marks: [
                                          {
                                            type: 'bold',
                                          },
                                        ],
                                        data: {},
                                      },
                                      {
                                        nodeType: 'text',
                                        value:
                                          ', one of the most common types of web-based attacks, where the attacker takes control of the web application’s database.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value: 'User privilege issues attacks ',
                                        marks: [
                                          {
                                            type: 'bold',
                                          },
                                        ],
                                        data: {},
                                      },
                                      {
                                        nodeType: 'text',
                                        value: 'where malicious employees gain access to sensitive information.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value: 'Memory corruption',
                                        marks: [
                                          {
                                            type: 'bold',
                                          },
                                        ],
                                        data: {},
                                      },
                                      {
                                        nodeType: 'text',
                                        value: ', which lets an attacker leak sensitive information or execute code.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value: 'Cross-site scripting',
                                        marks: [
                                          {
                                            type: 'bold',
                                          },
                                        ],
                                        data: {},
                                      },
                                      {
                                        nodeType: 'text',
                                        value:
                                          ', where attackers inject their own code to steal sensitive information.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value: 'Insecure server configuration attacks ',
                                        marks: [
                                          {
                                            type: 'bold',
                                          },
                                        ],
                                        data: {},
                                      },
                                      {
                                        nodeType: 'text',
                                        value: 'to expose critical or sensitive data.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  'After DAST alerts the development team that the scan identified security vulnerabilities, the team works to remediate the issues and protect their company’s brand and customers from the damaging consequences caused by cyberattacks and data breaches.',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.HEADING_3,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: 'DAST Pros',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.UL_LIST,
                            data: {},
                            content: [
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value:
                                          'Mimics a real-world malicious hacker to Identify security vulnerabilities that only occur in running applications. Other AppSec tools typically don’t find these issues.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value:
                                          'Generates few false positives (reports of vulnerabilities that aren’t present) compared to other methods.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value:
                                          'Can be run on any application since it doesn’t need access to source code. Therefore, one DAST tool can support all the development team’s applications.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.HEADING_3,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: 'DAST Cons',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.UL_LIST,
                            data: {},
                            content: [
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value: 'Might require security experts to run tests and interpret reports.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value: 'Scans might take a long time to complete.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value:
                                          'Can’t pinpoint the specific location of problematic code because it doesn’t work with the application’s source code.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.HEADING_2,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: 'DAST vs SAST',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  'Dynamic application security testing (DAST) is different from static application security testing (',
                                marks: [],
                                data: {},
                              },
                              {
                                nodeType: INLINES.HYPERLINK,
                                data: {
                                  uri: 'https://github.com/resources/articles/security/what-is-sast',
                                },
                                content: [
                                  {
                                    nodeType: 'text',
                                    value: 'SAST',
                                    marks: [],
                                    data: {},
                                  },
                                ],
                              },
                              {
                                nodeType: 'text',
                                value: '):',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.UL_LIST,
                            data: {},
                            content: [
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value:
                                          'DAST tools scan programs while they are executing to find security issues in the running application.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value:
                                          'SAST tools scan application source code or binary code when the application is not executing to identify potential vulnerabilities based on design or implementation.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  'Some SAST tools even scan code as it’s created. For example, a SAST code scanning product is natively embedded in ',
                                marks: [],
                                data: {},
                              },
                              {
                                nodeType: INLINES.HYPERLINK,
                                data: {
                                  uri: 'https://resources.github.com/appsec/',
                                },
                                content: [
                                  {
                                    nodeType: 'text',
                                    value: 'GitHub Advanced Security (GHAS)',
                                    marks: [],
                                    data: {},
                                  },
                                ],
                              },
                              {
                                nodeType: 'text',
                                value:
                                  ' to examine code as it’s written and integrate fixes natively into the developer workflow. This helps developers find and fix security issues in their code earlier to automate and scale application security.',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  'Developer teams looking to maximize application security use a combination of DAST and SAST tools to test their web applications. This best practice strengthens security by giving developers a comprehensive view of application vulnerabilities, both from an “outside in” hacker perspective with DAST and an “inside out” developer perspective with SAST.',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.HEADING_2,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: 'How to use DAST tools',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  'DAST tests are run in real time to help developers identify and fix security issues before the application is launched. The most effective strategy is to run DAST tests early in the SDLC, when it’s less costly and time-consuming to remediate vulnerabilities. Once the web application is in production, DAST continues to search for vulnerabilities, and sends alerts to the right people when remediation is needed.',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.HEADING_2,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: 'Build secure applications with DAST',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  'Web application cyberattacks are serious threats to businesses. By mimicking a malicious attacker who is trying to break into an application to steal data, DAST scanning exposes the most damaging security vulnerabilities, so development teams can fix them before the application is launched into production.',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: 'Using tools like DAST to stay ahead of security issues is a key component of ',
                                marks: [],
                                data: {},
                              },
                              {
                                nodeType: INLINES.HYPERLINK,
                                data: {
                                  uri: 'https://github.com/features/security',
                                },
                                content: [
                                  {
                                    nodeType: 'text',
                                    value: 'GitHub Security',
                                    marks: [],
                                    data: {},
                                  },
                                ],
                              },
                              {
                                nodeType: 'text',
                                value:
                                  '. Designed to help developers take a proactive security approach, GitHub Security natively embeds security tools directly into the ',
                                marks: [],
                                data: {},
                              },
                              {
                                nodeType: INLINES.HYPERLINK,
                                data: {
                                  uri: 'https://resources.github.com/devops/',
                                },
                                content: [
                                  {
                                    nodeType: 'text',
                                    value: 'DevOps',
                                    marks: [],
                                    data: {},
                                  },
                                ],
                              },
                              {
                                nodeType: 'text',
                                value: ' workflow, including:',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.UL_LIST,
                            data: {},
                            content: [
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value: '',
                                        marks: [],
                                        data: {},
                                      },
                                      {
                                        nodeType: INLINES.HYPERLINK,
                                        data: {
                                          uri: 'https://docs.github.com/en/code-security/code-scanning/automatically-scanning-your-code-for-vulnerabilities-and-errors/about-code-scanning',
                                        },
                                        content: [
                                          {
                                            nodeType: 'text',
                                            value: 'Code scanning',
                                            marks: [],
                                            data: {},
                                          },
                                        ],
                                      },
                                      {
                                        nodeType: 'text',
                                        value:
                                          ' scans for security issues as code is written and integrates fixes natively into the developer workflow.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value: '',
                                        marks: [],
                                        data: {},
                                      },
                                      {
                                        nodeType: INLINES.HYPERLINK,
                                        data: {
                                          uri: 'https://docs.github.com/en/code-security/secret-scanning/about-secret-scanning',
                                        },
                                        content: [
                                          {
                                            nodeType: 'text',
                                            value: 'Secret scanning',
                                            marks: [],
                                            data: {},
                                          },
                                        ],
                                      },
                                      {
                                        nodeType: 'text',
                                        value:
                                          ' prevents fraudulent use of leaked secrets that may have accidentally been pushed into code.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value: '',
                                        marks: [],
                                        data: {},
                                      },
                                      {
                                        nodeType: INLINES.HYPERLINK,
                                        data: {
                                          uri: 'https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/about-supply-chain-security',
                                        },
                                        content: [
                                          {
                                            nodeType: 'text',
                                            value: 'Supply chain security',
                                            marks: [],
                                            data: {},
                                          },
                                        ],
                                      },
                                      {
                                        nodeType: 'text',
                                        value:
                                          ' uses software composition analysis to catch vulnerable dependencies before they’re introduced into the codebase.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                              {
                                nodeType: BLOCKS.LIST_ITEM,
                                data: {},
                                content: [
                                  {
                                    nodeType: BLOCKS.PARAGRAPH,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: 'text',
                                        value: '',
                                        marks: [],
                                        data: {},
                                      },
                                      {
                                        nodeType: INLINES.HYPERLINK,
                                        data: {
                                          uri: 'https://docs.github.com/en/code-security/security-overview/about-the-security-overview',
                                        },
                                        content: [
                                          {
                                            nodeType: 'text',
                                            value: 'Security overview',
                                            marks: [],
                                            data: {},
                                          },
                                        ],
                                      },
                                      {
                                        nodeType: 'text',
                                        value:
                                          ' provides a centralized, single view of security risks across the entire enterprise.',
                                        marks: [],
                                        data: {},
                                      },
                                    ],
                                  },
                                ],
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value: 'In addition, third-party security capabilities are available through ',
                                marks: [],
                                data: {},
                              },
                              {
                                nodeType: INLINES.HYPERLINK,
                                data: {
                                  uri: 'https://github.com/features/actions',
                                },
                                content: [
                                  {
                                    nodeType: 'text',
                                    value: 'GitHub Actions',
                                    marks: [],
                                    data: {},
                                  },
                                ],
                              },
                              {
                                nodeType: 'text',
                                value:
                                  ', to give developers the freedom and extensibility to automate, customize, and execute their software workflows in the same place they code. This functionality empowers developers to use third-party SAST engines, DAST, infrastructure as code scanning (IaC), and container scanning.',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                          {
                            nodeType: BLOCKS.PARAGRAPH,
                            data: {},
                            content: [
                              {
                                nodeType: 'text',
                                value:
                                  'Together, GitHub Security, DAST, and third-party tools empower developer teams to secure their software and custom code across the software lifecycle.',
                                marks: [],
                                data: {},
                              },
                            ],
                          },
                        ],
                      },
                    },
                  },
                  rivers: [
                    {
                      sys: {
                        id: '3oDuNtIhzVyYybyHTahzO5',
                        contentType: {
                          sys: {
                            id: 'primerComponentRiver',
                          },
                        },
                      },
                      fields: {
                        align: 'start',
                        imageTextRatio: '60:40',
                        heading: 'What is GitHub Actions?',
                        text: {
                          nodeType: BLOCKS.DOCUMENT,
                          data: {},
                          content: [
                            {
                              data: {},
                              content: [
                                {
                                  data: {},
                                  marks: [],
                                  value:
                                    'GitHub Actions is an enterprise-grade CI/CD platform that allows you to automate, customize, and execute your software development workflows right in your repository.',
                                  nodeType: 'text',
                                },
                              ],
                              nodeType: BLOCKS.PARAGRAPH,
                            },
                          ],
                        },
                        videoSrc: 'https://www.youtube-nocookie.com/embed/URmeTqglS58',
                        hasShadow: false,
                      },
                    },
                    {
                      sys: {
                        id: '3sMpZ8i2LNWllmdih7Sgmb',
                        contentType: {
                          sys: {
                            id: 'primerComponentRiver',
                          },
                        },
                      },
                      fields: {
                        align: 'start',
                        imageTextRatio: '50:50',
                        heading: 'Secure Package Registry for Code and Workflows',
                        text: {
                          nodeType: BLOCKS.DOCUMENT,
                          data: {},
                          content: [
                            {
                              data: {},
                              content: [
                                {
                                  data: {},
                                  marks: [],
                                  value:
                                    'Securely store and manage your code and packages with GitHub credentials, integrated into your workflows via APIs and webhooks. Enjoy fast, reliable downloads through a global CDN for optimized performance.',
                                  nodeType: 'text',
                                },
                              ],
                              nodeType: BLOCKS.PARAGRAPH,
                            },
                            {
                              data: {},
                              content: [
                                {
                                  data: {},
                                  marks: [],
                                  value: '',
                                  nodeType: 'text',
                                },
                              ],
                              nodeType: BLOCKS.PARAGRAPH,
                            },
                          ],
                        },
                        callToAction: {
                          sys: {
                            id: 'fHifS5NvXtJS8b04alkjA',
                            contentType: {
                              sys: {
                                id: 'link',
                              },
                            },
                          },
                          fields: {
                            href: 'https://docs.github.com/packages',
                            text: 'Read the docs',
                            openInNewTab: false,
                          },
                        },
                        image: {
                          fields: {
                            description: '',
                            file: {
                              url: '//images.ctfassets.net/8aevphvgewt8/2nDndCZUe4d4pX9YAmJYlS/b6b6b59a1f53e18ae160434797661560/features-river-2-1.webp',
                            },
                          },
                        },
                        hasShadow: false,
                      },
                    },
                  ],
                  statistics: {
                    sys: {
                      id: '5o6a6ofl6Uqel2JxCfgIob',
                      contentType: {
                        sys: {
                          id: 'primerStatistics',
                        },
                      },
                    },
                    fields: {
                      statistics: [
                        {
                          sys: {
                            id: '1j500ScsIqFFqyjFPbVrVz',
                            contentType: {
                              sys: {
                                id: 'primerComponentStatistic',
                              },
                            },
                          },
                          fields: {
                            heading: '75%',
                            size: 'medium',
                            variant: 'boxed',
                            description: 'reduced time spent managing tools',
                            descriptionVariant: 'default',
                          },
                        },
                        {
                          sys: {
                            id: '3xYCCkxqsxG5s816ZQUVW5',
                            contentType: {
                              sys: {
                                id: 'primerComponentStatistic',
                              },
                            },
                          },
                          fields: {
                            heading: '433%',
                            size: 'medium',
                            variant: 'boxed',
                            description: 'ROI with GitHub Enterprise',
                            descriptionVariant: 'default',
                          },
                        },
                        {
                          sys: {
                            id: '5ge48ERp3A1aGJx89NODQC',
                            contentType: {
                              sys: {
                                id: 'primerComponentStatistic',
                              },
                            },
                          },
                          fields: {
                            heading: '77,000',
                            size: 'medium',
                            variant: 'boxed',
                            description: 'organizations using GitHub Copilot',
                            descriptionVariant: 'default',
                          },
                        },
                        {
                          sys: {
                            id: '3xYCCkxqsxG5s816ZQUVW5',
                            contentType: {
                              sys: {
                                id: 'primerComponentStatistic',
                              },
                            },
                          },
                          fields: {
                            heading: '433%',
                            size: 'medium',
                            variant: 'boxed',
                            description: 'ROI with GitHub Enterprise',
                            descriptionVariant: 'default',
                          },
                        },
                      ],
                    },
                  },
                  visualSettings: {
                    sys: {
                      id: '77TiIZhUKUhdHmema5HMtt',
                      contentType: {
                        sys: {
                          id: 'flexSectionVisualSettings',
                        },
                      },
                    },
                    fields: {
                      paddingBlockStart: 'spacious',
                      paddingBlockEnd: 'spacious',
                      backgroundColor: 'default',
                      roundedCorners: true,
                      verticalGap: 'spacious',
                    },
                  },
                },
              },
            ],
            ctaBanner: {
              sys: {
                id: 'j9cLWHIqQ7b5leFoB8hjZ',
                contentType: {
                  sys: {
                    id: 'primerComponentCtaBanner',
                  },
                },
              },
              fields: {
                align: 'center',
                heading: 'Maximize your investment in AI',
                description: {
                  nodeType: BLOCKS.DOCUMENT,
                  data: {},
                  content: [
                    {
                      data: {},
                      content: [
                        {
                          data: {},
                          marks: [],
                          value:
                            'Our recent study with Accenture shows that AI-driven tools like GitHub Copilot, when integrated into daily workflows, can significantly boost productivity, job satisfaction, and overall code quality without adding complexity.',
                          nodeType: 'text',
                        },
                      ],
                      nodeType: BLOCKS.PARAGRAPH,
                    },
                    {
                      data: {},
                      content: [
                        {
                          data: {},
                          marks: [],
                          value: '\n',
                          nodeType: 'text',
                        },
                      ],
                      nodeType: BLOCKS.PARAGRAPH,
                    },
                    {
                      data: {},
                      content: [
                        {
                          data: {},
                          marks: [],
                          value:
                            'Discover how to seamlessly integrate AI into your development processes with GitHub Copilot and see measurable impact across your organization.',
                          nodeType: 'text',
                        },
                      ],
                      nodeType: BLOCKS.PARAGRAPH,
                    },
                    {
                      data: {},
                      content: [
                        {
                          data: {},
                          marks: [],
                          value: '\n',
                          nodeType: 'text',
                        },
                      ],
                      nodeType: BLOCKS.PARAGRAPH,
                    },
                  ],
                },
                hasBorder: true,
                hasShadow: true,
                hasBackground: true,
                callToActionPrimary: {
                  sys: {
                    id: '2hS1p3E1NVBZu0TFyxoAXQ',
                    contentType: {
                      sys: {
                        id: 'link',
                      },
                    },
                  },
                  fields: {
                    href: 'https://github.blog/news-insights/research/research-quantifying-github-copilots-impact-in-the-enterprise-with-accenture/',
                    text: 'Learn more',
                    openInNewTab: false,
                  },
                },
                callToActionSecondary: {
                  sys: {
                    id: 'OEGOmi1BUJq0RosB33bNc',
                    contentType: {
                      sys: {
                        id: 'link',
                      },
                    },
                  },
                  fields: {
                    href: 'https://github.com/enterprise/contact?ref_cta=Contact+sales&ref_loc=footer&ref_page=%2Fsolutions_executive_insights',
                    text: 'Contact sales',
                    openInNewTab: false,
                  },
                },
              },
            },
            faq: {
              sys: {
                id: 'PRiFZKu7L6DnPyibZjQzc',
                contentType: {
                  sys: {
                    id: 'primerComponentFaqGroup',
                  },
                },
              },
              fields: {
                heading: 'Frequently asked questions',
                faqs: [
                  {
                    sys: {
                      id: '5MP6gwMGh01uvNLv98OPkx',
                      contentType: {
                        sys: {
                          id: 'primerComponentFaq',
                        },
                      },
                    },
                    fields: {
                      heading: 'General',
                      blocks: [
                        {
                          sys: {
                            id: '1xq98hWsP60k7UCCt0BwDV',
                            contentType: {
                              sys: {
                                id: 'primerComponentFaqBlock',
                              },
                            },
                          },
                          fields: {
                            questions: [
                              {
                                sys: {
                                  id: '6FQprhXlRLGYbJ9DnjE6s0',
                                  contentType: {
                                    sys: {
                                      id: 'primerComponentFaqQuestion',
                                    },
                                  },
                                },
                                fields: {
                                  question: 'What’s included in the GitHub for Startups offer?',
                                  answer: {
                                    nodeType: BLOCKS.DOCUMENT,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: BLOCKS.PARAGRAPH,
                                        data: {},
                                        content: [
                                          {
                                            nodeType: 'text',
                                            value:
                                              'All GitHub for Startups companies receive up to 20 seats of GitHub Enterprise for free for 12 months*. Learn more about the features and capabilities of GitHub Enterprise ',
                                            marks: [],
                                            data: {},
                                          },
                                          {
                                            nodeType: INLINES.HYPERLINK,
                                            data: {
                                              uri: 'https://github.com/enterprise',
                                            },
                                            content: [
                                              {
                                                nodeType: 'text',
                                                value: 'here',
                                                marks: [],
                                                data: {},
                                              },
                                            ],
                                          },
                                          {
                                            nodeType: 'text',
                                            value: '.',
                                            marks: [],
                                            data: {},
                                          },
                                        ],
                                      },
                                      {
                                        nodeType: BLOCKS.PARAGRAPH,
                                        data: {},
                                        content: [
                                          {
                                            nodeType: 'text',
                                            value: '*',
                                            marks: [],
                                            data: {},
                                          },
                                          {
                                            nodeType: 'text',
                                            value:
                                              'Startups affiliated with a GitHub for Startups VC or accelerator partner may be eligible for additional discounts and benefits. See list of partners ',
                                            marks: [],
                                            data: {},
                                          },
                                          {
                                            nodeType: INLINES.HYPERLINK,
                                            data: {
                                              uri: 'https://github.com/enterprise/startups/partners',
                                            },
                                            content: [
                                              {
                                                nodeType: 'text',
                                                value: 'here',
                                                marks: [],
                                                data: {},
                                              },
                                            ],
                                          },
                                          {
                                            nodeType: 'text',
                                            value: '. Don’t see your partner? Share ',
                                            marks: [],
                                            data: {},
                                          },
                                          {
                                            nodeType: INLINES.HYPERLINK,
                                            data: {
                                              uri: 'https://github.com/enterprise/startups#join-partners',
                                            },
                                            content: [
                                              {
                                                nodeType: 'text',
                                                value: 'this link',
                                                marks: [],
                                                data: {},
                                              },
                                            ],
                                          },
                                          {
                                            nodeType: 'text',
                                            value: ' to refer your partner to the GitHub for Startups partner program.',
                                            marks: [],
                                            data: {},
                                          },
                                        ],
                                      },
                                    ],
                                  },
                                },
                              },
                              {
                                sys: {
                                  id: '6KcqdAJnM33XFsBuEEAOOP',
                                  contentType: {
                                    sys: {
                                      id: 'primerComponentFaqQuestion',
                                    },
                                  },
                                },
                                fields: {
                                  question: 'Who is eligible to apply?',
                                  answer: {
                                    nodeType: BLOCKS.DOCUMENT,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: BLOCKS.PARAGRAPH,
                                        data: {},
                                        content: [
                                          {
                                            nodeType: 'text',
                                            value:
                                              'Startups that meet the following criteria are eligible to apply for the GitHub for Startups program:',
                                            marks: [],
                                            data: {},
                                          },
                                        ],
                                      },
                                      {
                                        nodeType: BLOCKS.OL_LIST,
                                        data: {},
                                        content: [
                                          {
                                            nodeType: BLOCKS.LIST_ITEM,
                                            data: {},
                                            content: [
                                              {
                                                nodeType: BLOCKS.PARAGRAPH,
                                                data: {},
                                                content: [
                                                  {
                                                    nodeType: 'text',
                                                    value: 'Received outside funding (up to Series A)',
                                                    marks: [],
                                                    data: {},
                                                  },
                                                ],
                                              },
                                            ],
                                          },
                                          {
                                            nodeType: BLOCKS.LIST_ITEM,
                                            data: {},
                                            content: [
                                              {
                                                nodeType: BLOCKS.PARAGRAPH,
                                                data: {},
                                                content: [
                                                  {
                                                    nodeType: 'text',
                                                    value: 'New to GitHub Enterprise',
                                                    marks: [],
                                                    data: {},
                                                  },
                                                ],
                                              },
                                            ],
                                          },
                                          {
                                            nodeType: BLOCKS.LIST_ITEM,
                                            data: {},
                                            content: [
                                              {
                                                nodeType: BLOCKS.PARAGRAPH,
                                                data: {},
                                                content: [
                                                  {
                                                    nodeType: 'text',
                                                    value:
                                                      'Must not have previously received credits for GitHub Enterprise',
                                                    marks: [],
                                                    data: {},
                                                  },
                                                ],
                                              },
                                            ],
                                          },
                                        ],
                                      },
                                      {
                                        nodeType: BLOCKS.PARAGRAPH,
                                        data: {},
                                        content: [
                                          {
                                            nodeType: 'text',
                                            value: '',
                                            marks: [],
                                            data: {},
                                          },
                                        ],
                                      },
                                    ],
                                  },
                                },
                              },
                              {
                                sys: {
                                  id: 'WMVbSzas5azLOYp8M0XcW',
                                  contentType: {
                                    sys: {
                                      id: 'primerComponentFaqQuestion',
                                    },
                                  },
                                },
                                fields: {
                                  question: 'Is my startup considered an early-stage startup?',
                                  answer: {
                                    nodeType: BLOCKS.DOCUMENT,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: BLOCKS.PARAGRAPH,
                                        data: {},
                                        content: [
                                          {
                                            nodeType: 'text',
                                            value:
                                              'If your startup has received outside funding (Series B or earlier), you are classified as an early-stage startup.',
                                            marks: [],
                                            data: {},
                                          },
                                        ],
                                      },
                                    ],
                                  },
                                },
                              },
                              {
                                sys: {
                                  id: 'WtCPBW7nf2JfgGlTaQ6eE',
                                  contentType: {
                                    sys: {
                                      id: 'primerComponentFaqQuestion',
                                    },
                                  },
                                },
                                fields: {
                                  question: "Am I eligible for credits if I'm new to GitHub Enterprise?",
                                  answer: {
                                    nodeType: BLOCKS.DOCUMENT,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: BLOCKS.PARAGRAPH,
                                        data: {},
                                        content: [
                                          {
                                            nodeType: 'text',
                                            value:
                                              'Yes, if you are new or returning to GitHub Enterprise and have not previously received credits, you are eligible to receive credits.',
                                            marks: [],
                                            data: {},
                                          },
                                        ],
                                      },
                                    ],
                                  },
                                },
                              },
                              {
                                sys: {
                                  id: '21l3mwwqRxTWlbKtZ1YTWR',
                                  contentType: {
                                    sys: {
                                      id: 'primerComponentFaqQuestion',
                                    },
                                  },
                                },
                                fields: {
                                  question: 'What does it mean to be "new or returning" to GitHub Enterprise?',
                                  answer: {
                                    nodeType: BLOCKS.DOCUMENT,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: BLOCKS.PARAGRAPH,
                                        data: {},
                                        content: [
                                          {
                                            nodeType: 'text',
                                            value:
                                              'This refers to users who are either using GitHub Enterprise for the first time or have previously used it but did not receive credits in the past.',
                                            marks: [],
                                            data: {},
                                          },
                                        ],
                                      },
                                    ],
                                  },
                                },
                              },
                              {
                                sys: {
                                  id: '78dy7cNCu9CG4QlIxEG9Na',
                                  contentType: {
                                    sys: {
                                      id: 'primerComponentFaqQuestion',
                                    },
                                  },
                                },
                                fields: {
                                  question:
                                    'What if my startup is not eligible for GitHub for Startups? Are there other resources for me?',
                                  answer: {
                                    nodeType: BLOCKS.DOCUMENT,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: BLOCKS.PARAGRAPH,
                                        data: {},
                                        content: [
                                          {
                                            nodeType: 'text',
                                            value:
                                              'If you’re not currently eligible for GitHub for Startups but would like to try GitHub Enterprise, please feel to sign up for a trial ',
                                            marks: [],
                                            data: {},
                                          },
                                          {
                                            nodeType: INLINES.HYPERLINK,
                                            data: {
                                              uri: 'https://github.com/account/organizations/new?plan=business_plus&ref_cta=Start%2520a%2520free%2520trial&ref_loc=cards&ref_page=%2Fpricing',
                                            },
                                            content: [
                                              {
                                                nodeType: 'text',
                                                value: 'here',
                                                marks: [],
                                                data: {},
                                              },
                                            ],
                                          },
                                          {
                                            nodeType: 'text',
                                            value: '.',
                                            marks: [],
                                            data: {},
                                          },
                                        ],
                                      },
                                    ],
                                  },
                                },
                              },
                              {
                                sys: {
                                  id: '1VXZdyIcUUIbsD68vkaSzE',
                                  contentType: {
                                    sys: {
                                      id: 'primerComponentFaqQuestion',
                                    },
                                  },
                                },
                                fields: {
                                  question: 'How can my organization become a GitHub for Startups partner?',
                                  answer: {
                                    nodeType: BLOCKS.DOCUMENT,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: BLOCKS.PARAGRAPH,
                                        data: {},
                                        content: [
                                          {
                                            nodeType: 'text',
                                            value:
                                              'Any investor, accelerator, or startup support organization is eligible to apply for the GitHub for Startups program. Apply ',
                                            marks: [],
                                            data: {},
                                          },
                                          {
                                            nodeType: INLINES.HYPERLINK,
                                            data: {
                                              uri: 'https://github.com/enterprise/startups/#join-partners',
                                            },
                                            content: [
                                              {
                                                nodeType: 'text',
                                                value: 'here',
                                                marks: [],
                                                data: {},
                                              },
                                            ],
                                          },
                                          {
                                            nodeType: 'text',
                                            value: '.',
                                            marks: [],
                                            data: {},
                                          },
                                        ],
                                      },
                                    ],
                                  },
                                },
                              },
                            ],
                          },
                        },
                      ],
                    },
                  },
                  {
                    sys: {
                      id: '2AbyBPoeZ9rWAp14AOFu7a',
                      contentType: {
                        sys: {
                          id: 'primerComponentFaq',
                        },
                      },
                    },
                    fields: {
                      heading: 'Become a partner',
                      blocks: [
                        {
                          sys: {
                            id: '4kzac1sIPoSTtCgL3m4uZI',
                            contentType: {
                              sys: {
                                id: 'primerComponentFaqBlock',
                              },
                            },
                          },
                          fields: {
                            questions: [
                              {
                                sys: {
                                  id: '1mr1h6UWG59Pd4ddGspsDF',
                                  contentType: {
                                    sys: {
                                      id: 'primerComponentFaqQuestion',
                                    },
                                  },
                                },
                                fields: {
                                  question: 'How can I apply to become an investor partner?',
                                  answer: {
                                    nodeType: BLOCKS.DOCUMENT,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: BLOCKS.PARAGRAPH,
                                        data: {},
                                        content: [
                                          {
                                            nodeType: 'text',
                                            value: 'You can apply to be an investor partner by applying on our ',
                                            marks: [],
                                            data: {},
                                          },
                                          {
                                            nodeType: INLINES.HYPERLINK,
                                            data: {
                                              uri: '#',
                                            },
                                            content: [
                                              {
                                                nodeType: 'text',
                                                value: 'application page',
                                                marks: [],
                                                data: {},
                                              },
                                            ],
                                          },
                                          {
                                            nodeType: 'text',
                                            value: '.',
                                            marks: [],
                                            data: {},
                                          },
                                        ],
                                      },
                                    ],
                                  },
                                },
                              },
                              {
                                sys: {
                                  id: '58Xd53jSlvxscvOd0s5s8b',
                                  contentType: {
                                    sys: {
                                      id: 'primerComponentFaqQuestion',
                                    },
                                  },
                                },
                                fields: {
                                  question: 'What types of organizations can become partners?',
                                  answer: {
                                    nodeType: BLOCKS.DOCUMENT,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: BLOCKS.PARAGRAPH,
                                        data: {},
                                        content: [
                                          {
                                            nodeType: 'text',
                                            value:
                                              'We partner with leading investors, accelerators, and startup support organizations that are dedicated to helping early-stage startups succeed.',
                                            marks: [],
                                            data: {},
                                          },
                                        ],
                                      },
                                    ],
                                  },
                                },
                              },
                              {
                                sys: {
                                  id: '70Fw3JN3WKMXkNycovzpAp',
                                  contentType: {
                                    sys: {
                                      id: 'primerComponentFaqQuestion',
                                    },
                                  },
                                },
                                fields: {
                                  question: 'Are there any costs associated with becoming a partner?',
                                  answer: {
                                    nodeType: BLOCKS.DOCUMENT,
                                    data: {},
                                    content: [
                                      {
                                        nodeType: BLOCKS.PARAGRAPH,
                                        data: {},
                                        content: [
                                          {
                                            nodeType: 'text',
                                            value: 'Please refer to our ',
                                            marks: [],
                                            data: {},
                                          },
                                          {
                                            nodeType: INLINES.HYPERLINK,
                                            data: {
                                              uri: '#',
                                            },
                                            content: [
                                              {
                                                nodeType: 'text',
                                                value: 'partnership guidelines',
                                                marks: [],
                                                data: {},
                                              },
                                            ],
                                          },
                                          {
                                            nodeType: 'text',
                                            value:
                                              ' for specific details regarding any costs or requirements associated with becoming a partner.',
                                            marks: [],
                                            data: {},
                                          },
                                        ],
                                      },
                                    ],
                                  },
                                },
                              },
                            ],
                          },
                        },
                      ],
                    },
                  },
                ],
              },
            },
            visualSettings: {
              sys: {
                id: '4cNX3bgs5LGwnyXPg2uaN5',
                contentType: {
                  sys: {
                    id: 'flexTemplateVisualSettings',
                  },
                },
              },
              fields: {
                trailingSectionRoundedCorners: true,
                trailingSectionBackgroundColor: 'subtle',
              },
            },
          },
        },
        title: 'Sample Flex Template',
      },
    },
  },
}

export const WithBreadcrumbs: Story = {
  args: {
    page: {
      sys: {
        id: '2UfXY5jRH7icoMDJnmPdQT',
        contentType: {
          sys: {
            id: 'containerPage',
          },
        },
      },
      fields: {
        path: '/contentful-lp-tests/template-flex',
        settings: {
          sys: {
            id: 'GljhrODli6AFEilSnxHPA',
            contentType: {
              sys: {
                id: 'pageSettings',
              },
            },
          },
          fields: {
            colorMode: 'dark',
          },
        },
        template: {
          sys: {
            id: '1Cr3de1nTcfeUsDvJyqfBs',
            contentType: {
              sys: {
                id: 'templateFlex',
              },
            },
          },
          fields: {
            breadcrumbs: [
              {
                sys: {
                  id: '3sKZC4xN2iI7ZQNe67u7Qc',
                  contentType: {
                    sys: {
                      id: 'primerComponentBreadcrumb',
                    },
                  },
                },
                fields: {
                  pageName: 'Github',
                  path: '/',
                  selected: false,
                },
              },
              {
                sys: {
                  id: '2K1uZ0LfldssUOdNSEwPY',
                  contentType: {
                    sys: {
                      id: 'primerComponentBreadcrumb',
                    },
                  },
                },
                fields: {
                  pageName: 'Contentful LP Test',
                  path: '/contentful-lp-test',
                  selected: false,
                },
              },
              {
                sys: {
                  id: '3aKzjXZN9SMfEgldSel7sM',
                  contentType: {
                    sys: {
                      id: 'primerComponentBreadcrumb',
                    },
                  },
                },
                fields: {
                  pageName: 'Flex Template',
                  path: '/contentful-lp-tests/template-flex',
                  selected: true,
                },
              },
            ],
            hero: {
              sys: {
                id: '6W6CtI32cMuL7Paxj2aOSu',
                contentType: {
                  sys: {
                    id: 'primerComponentHero',
                  },
                },
              },
              fields: {
                align: 'start',
                label: 'GitHub Education',
                heading: 'Connect and collaborate with educators and students worldwide',
                imagePosition: 'Block',
                description: 'Join us in our mission to empower the next generation of developers',
                callToActionPrimary: {
                  sys: {
                    id: '1V7oIvAQ6rtUKhomlDE4Tg',
                    contentType: {
                      sys: {
                        id: 'link',
                      },
                    },
                  },
                  fields: {
                    href: 'https://survey3.medallia.com/?IqFRAo-edu-partnership',
                    text: 'Partner with GitHub Education',
                    openInNewTab: false,
                  },
                },
              },
            },
            heroBackgroundImage: {
              sys: {
                id: '22Wfu01rB6ZJuKsz07b3UC',
                contentType: {
                  sys: {
                    id: 'backgroundImage',
                  },
                },
              },
              fields: {
                image: {
                  fields: {
                    description: 'A group of people working on laptops with abstract shapes and calendars',
                    file: {
                      url: '//images.ctfassets.net/8aevphvgewt8/131JffhVIrbXCclE3QUlYn/9e51844548d4dd7b1780d8ef651e9a47/partners.webp',
                    },
                  },
                },
                focus: 'left',
                colorMode: 'dark',
              },
            },
            sections: [],
            visualSettings: {
              sys: {
                id: '4cNX3bgs5LGwnyXPg2uaN5',
                contentType: {
                  sys: {
                    id: 'flexTemplateVisualSettings',
                  },
                },
              },
              fields: {
                trailingSectionRoundedCorners: true,
                trailingSectionBackgroundColor: 'subtle',
              },
            },
          },
        },
        title: 'Sample Flex Template',
      },
    },
  },
}

export const WithVisualSettings: Story = {
  args: {
    page: {
      sys: {
        id: '2UfXY5jRH7icoMDJnmPdQT',
        contentType: {
          sys: {
            id: 'containerPage',
          },
        },
      },
      fields: {
        path: '/contentful-lp-tests/template-flex',
        settings: {
          sys: {
            id: 'GljhrODli6AFEilSnxHPA',
            contentType: {
              sys: {
                id: 'pageSettings',
              },
            },
          },
          fields: {
            colorMode: 'dark',
          },
        },
        template: {
          sys: {
            id: '1Cr3de1nTcfeUsDvJyqfBs',
            contentType: {
              sys: {
                id: 'templateFlex',
              },
            },
          },
          fields: {
            breadcrumbs: [
              {
                sys: {
                  id: '3sKZC4xN2iI7ZQNe67u7Qc',
                  contentType: {
                    sys: {
                      id: 'primerComponentBreadcrumb',
                    },
                  },
                },
                fields: {
                  pageName: 'GitHub',
                  path: '/',
                  selected: false,
                },
              },
              {
                sys: {
                  id: '2K1uZ0LfldssUOdNSEwPY',
                  contentType: {
                    sys: {
                      id: 'primerComponentBreadcrumb',
                    },
                  },
                },
                fields: {
                  pageName: 'Contentful LP Test',
                  path: '/contentful-lp-test',
                  selected: false,
                },
              },
              {
                sys: {
                  id: '3aKzjXZN9SMfEgldSel7sM',
                  contentType: {
                    sys: {
                      id: 'primerComponentBreadcrumb',
                    },
                  },
                },
                fields: {
                  pageName: 'Flex Template',
                  path: '/contentful-lp-tests/template-flex',
                  selected: true,
                },
              },
            ],
            hero: {
              sys: {
                id: '6W6CtI32cMuL7Paxj2aOSu',
                contentType: {
                  sys: {
                    id: 'primerComponentHero',
                  },
                },
              },
              fields: {
                align: 'start',
                label: 'GitHub Education',
                heading: 'Connect and collaborate with educators and students worldwide',
                imagePosition: 'Block',
                description: 'Join us in our mission to empower the next generation of developers',
                callToActionPrimary: {
                  sys: {
                    id: '1V7oIvAQ6rtUKhomlDE4Tg',
                    contentType: {
                      sys: {
                        id: 'link',
                      },
                    },
                  },
                  fields: {
                    href: 'https://survey3.medallia.com/?IqFRAo-edu-partnership',
                    text: 'Partner with GitHub Education',
                    openInNewTab: false,
                  },
                },
              },
            },
            heroBackgroundImage: {
              sys: {
                id: '22Wfu01rB6ZJuKsz07b3UC',
                contentType: {
                  sys: {
                    id: 'backgroundImage',
                  },
                },
              },
              fields: {
                image: {
                  fields: {
                    description: 'A group of people working on laptops with abstract shapes and calendars',
                    file: {
                      url: '//images.ctfassets.net/8aevphvgewt8/131JffhVIrbXCclE3QUlYn/9e51844548d4dd7b1780d8ef651e9a47/partners.webp',
                    },
                  },
                },
                focus: 'left',
                colorMode: 'dark',
              },
            },
            sections: [],
            visualSettings: {
              sys: {
                id: '4cNX3bgs5LGwnyXPg2uaN5',
                contentType: {
                  sys: {
                    id: 'flexTemplateVisualSettings',
                  },
                },
              },
              fields: {
                heroPaddingBlockEnd: 'condensed',
                trailingSectionRoundedCorners: true,
                trailingSectionBackgroundColor: 'subtle',
              },
            },
          },
        },
        title: 'Sample Flex Template',
      },
    },
  },
}

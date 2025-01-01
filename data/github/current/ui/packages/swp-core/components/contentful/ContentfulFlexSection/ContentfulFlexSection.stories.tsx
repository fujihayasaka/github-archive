import '@primer/react-brand/lib/css/main.css'

import type {Meta, StoryObj} from '@storybook/react'

import {ContentfulFlexSection} from './ContentfulFlexSection'
import {ThemeProvider} from '@primer/react-brand'
import {BLOCKS, INLINES} from '@contentful/rich-text-types'

const meta: Meta<typeof ContentfulFlexSection> = {
  title: 'Mkt/Swp/Contentful/ContentfulFlexSection',
  component: ContentfulFlexSection,
}

export default meta

type Story = StoryObj<typeof ContentfulFlexSection>

export const Default: Story = {
  args: {
    component: {
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
                            value: 'Total page views to Discussions segmented by logged in vs anonymous users.',
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
                              value: 'The ability to store your code and repository data in your preferred region',
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
  },
}

export const DarkMode: Story = {
  args: {
    // @ts-expect-error - Default.args will always be defined in this story
    component: Default.args.component,
  },
  render: args => (
    <ThemeProvider colorMode="dark">
      <ContentfulFlexSection {...args} />
    </ThemeProvider>
  ),
}

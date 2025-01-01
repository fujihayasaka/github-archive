export default {
  contentfulRawJsonResponse: {
    title: '/resources/whitepapers/whitepaper-test',
    sys: {
      type: 'Array',
    },
    total: 1,
    skip: 0,
    limit: 1000,
    items: [
      {
        metadata: {
          tags: [],
          concepts: [],
        },
        sys: {
          space: {
            sys: {
              type: 'Link',
              linkType: 'Space',
              id: 'cool-space-id',
            },
          },
          id: '5fXgCL1UGx02LtlYDMHrmy',
          type: 'Entry',
          createdAt: '2024-11-22T19:55:37.312Z',
          updatedAt: '2024-11-22T19:55:37.312Z',
          environment: {
            sys: {
              id: 'cool-environment-name',
              type: 'Link',
              linkType: 'Environment',
            },
          },
          publishedVersion: 5,
          revision: 1,
          contentType: {
            sys: {
              type: 'Link',
              linkType: 'ContentType',
              id: 'containerPage',
            },
          },
          locale: 'en-US',
        },
        fields: {
          title: 'Whitepaper Test',
          path: '/resources/whitepapers/whitepaper-test',
          template: {
            sys: {
              type: 'Link',
              linkType: 'Entry',
              id: '57NaV83tSwkRstIFB8dsPh',
            },
          },
        },
      },
    ],
    includes: {
      Entry: [
        {
          metadata: {
            tags: [],
            concepts: [],
          },
          sys: {
            space: {
              sys: {
                type: 'Link',
                linkType: 'Space',
                id: 'cool-space-id',
              },
            },
            id: '0r6rf4ALDvSYCbWF9gG2W',
            type: 'Entry',
            createdAt: '2024-11-22T19:53:50.972Z',
            updatedAt: '2024-11-22T19:53:50.972Z',
            environment: {
              sys: {
                id: 'cool-environment-name',
                type: 'Link',
                linkType: 'Environment',
              },
            },
            publishedVersion: 2,
            revision: 1,
            contentType: {
              sys: {
                type: 'Link',
                linkType: 'ContentType',
                id: 'primerComponentProse',
              },
            },
            locale: 'en-US',
          },
          fields: {
            title: 'Whitepaper Test',
            text: {
              nodeType: 'document',
              data: {},
              content: [
                {
                  nodeType: 'paragraph',
                  data: {},
                  content: [
                    {
                      nodeType: 'text',
                      value:
                        'Eleifend amet donec ligula etiam massa cursus sodales a pharetra posuere suspendisse malesuada. ',
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
          metadata: {
            tags: [],
            concepts: [],
          },
          sys: {
            space: {
              sys: {
                type: 'Link',
                linkType: 'Space',
                id: 'cool-space-id',
              },
            },
            id: '14Kb2KcAUpJAgQxXUycgjh',
            type: 'Entry',
            createdAt: '2024-11-22T19:51:50.327Z',
            updatedAt: '2024-11-22T19:51:50.327Z',
            environment: {
              sys: {
                id: 'cool-environment-name',
                type: 'Link',
                linkType: 'Environment',
              },
            },
            publishedVersion: 2,
            revision: 1,
            contentType: {
              sys: {
                type: 'Link',
                linkType: 'ContentType',
                id: 'marketoCampaign',
              },
            },
            locale: 'en-US',
          },
          fields: {
            title: 'Example',
            cDLProgramName: 'example',
            sFDCLastCampaignStatus: 'Registered',
            source: 'example',
          },
        },
        {
          metadata: {
            tags: [],
            concepts: [],
          },
          sys: {
            space: {
              sys: {
                type: 'Link',
                linkType: 'Space',
                id: 'cool-space-id',
              },
            },
            id: '22VopkBSHugfo49RrhwsI1',
            type: 'Entry',
            createdAt: '2024-11-22T19:55:21.778Z',
            updatedAt: '2024-11-22T19:55:21.778Z',
            environment: {
              sys: {
                id: 'cool-environment-name',
                type: 'Link',
                linkType: 'Environment',
              },
            },
            publishedVersion: 3,
            revision: 1,
            contentType: {
              sys: {
                type: 'Link',
                linkType: 'ContentType',
                id: 'formLayout',
              },
            },
            locale: 'en-US',
          },
          fields: {
            title: 'Example Fields',
            formFields: [
              {
                sys: {
                  type: 'Link',
                  linkType: 'Entry',
                  id: '4Fm3igJ6TkIQFs1hovMEGG',
                },
              },
            ],
          },
        },
        {
          metadata: {
            tags: [],
            concepts: [],
          },
          sys: {
            space: {
              sys: {
                type: 'Link',
                linkType: 'Space',
                id: 'cool-space-id',
              },
            },
            id: '2earrkEFekIVqpWE4h4gMu',
            type: 'Entry',
            createdAt: '2024-11-22T19:55:25.582Z',
            updatedAt: '2024-11-22T19:55:25.582Z',
            environment: {
              sys: {
                id: 'cool-environment-name',
                type: 'Link',
                linkType: 'Environment',
              },
            },
            publishedVersion: 6,
            revision: 1,
            contentType: {
              sys: {
                type: 'Link',
                linkType: 'ContentType',
                id: 'form',
              },
            },
            locale: 'en-US',
          },
          fields: {
            title: '/resources/whitepapers/whitepaper-test WhitePaper Form',
            heading: {
              data: {},
              content: [
                {
                  data: {},
                  content: [
                    {
                      data: {},
                      marks: [],
                      value: 'Metus maecenas quis urna laoreet posuere massa porttitor eleifend posuere aliquet.',
                      nodeType: 'text',
                    },
                  ],
                  nodeType: 'paragraph',
                },
              ],
              nodeType: 'document',
            },
            submitText: 'Submit',
            layout: {
              sys: {
                type: 'Link',
                linkType: 'Entry',
                id: '22VopkBSHugfo49RrhwsI1',
              },
            },
            campaign: {
              sys: {
                type: 'Link',
                linkType: 'Entry',
                id: '14Kb2KcAUpJAgQxXUycgjh',
              },
            },
          },
        },
        {
          metadata: {
            tags: [],
            concepts: [],
          },
          sys: {
            space: {
              sys: {
                type: 'Link',
                linkType: 'Space',
                id: 'cool-space-id',
              },
            },
            id: '4Fm3igJ6TkIQFs1hovMEGG',
            type: 'Entry',
            createdAt: '2024-11-22T19:55:05.205Z',
            updatedAt: '2024-11-22T19:55:05.205Z',
            environment: {
              sys: {
                id: 'cool-environment-name',
                type: 'Link',
                linkType: 'Environment',
              },
            },
            publishedVersion: 3,
            revision: 1,
            contentType: {
              sys: {
                type: 'Link',
                linkType: 'ContentType',
                id: 'formFieldTextInput',
              },
            },
            locale: 'en-US',
          },
          fields: {
            title: 'Email',
            type: 'email',
            label: 'Email',
            placeholder: 'your-email@provider.com',
            htmlName: 'email',
          },
        },
        {
          metadata: {
            tags: [],
            concepts: [],
          },
          sys: {
            space: {
              sys: {
                type: 'Link',
                linkType: 'Space',
                id: 'cool-space-id',
              },
            },
            id: '57NaV83tSwkRstIFB8dsPh',
            type: 'Entry',
            createdAt: '2024-11-22T19:55:29.155Z',
            updatedAt: '2024-11-22T19:55:29.155Z',
            environment: {
              sys: {
                id: 'cool-environment-name',
                type: 'Link',
                linkType: 'Environment',
              },
            },
            publishedVersion: 10,
            revision: 1,
            contentType: {
              sys: {
                type: 'Link',
                linkType: 'ContentType',
                id: 'templateWhitepaper',
              },
            },
            locale: 'en-US',
          },
          fields: {
            title: '/resources/whitepapers/whitepaper-test Template',
            contentType: 'Whitepaper',
            heading: 'Really Cool Test',
            publishedDate: '2024-11-22',
            excerpt: {
              data: {},
              content: [
                {
                  data: {},
                  content: [
                    {
                      data: {},
                      marks: [],
                      value: 'Lorem ipsum dolor sit amet ullamcorper fringilla suspendisse semper vulputate aliquet.',
                      nodeType: 'text',
                    },
                  ],
                  nodeType: 'paragraph',
                },
                {
                  data: {},
                  content: [
                    {
                      data: {},
                      marks: [],
                      value: 'Fringilla sodales dictumst leo consectetur maecenas duis habitasse.',
                      nodeType: 'text',
                    },
                  ],
                  nodeType: 'paragraph',
                },
                {
                  data: {},
                  content: [
                    {
                      data: {},
                      marks: [],
                      value:
                        'Dictumst ut aliquam nibh integer nibh vitae convallis pharetra ut convallis viverra adipiscing platea.',
                      nodeType: 'text',
                    },
                  ],
                  nodeType: 'paragraph',
                },
              ],
              nodeType: 'document',
            },
            lede: {
              data: {},
              content: [
                {
                  data: {},
                  content: [
                    {
                      data: {},
                      marks: [],
                      value: 'Lorem ipsum dolor sit amet ullamcorper fringilla suspendisse semper vulputate aliquet.',
                      nodeType: 'text',
                    },
                  ],
                  nodeType: 'paragraph',
                },
                {
                  data: {},
                  content: [
                    {
                      data: {},
                      marks: [],
                      value: 'Fringilla sodales dictumst leo consectetur maecenas duis habitasse.',
                      nodeType: 'text',
                    },
                  ],
                  nodeType: 'paragraph',
                },
                {
                  data: {},
                  content: [
                    {
                      data: {},
                      marks: [],
                      value:
                        'Dictumst ut aliquam nibh integer nibh vitae convallis pharetra ut convallis viverra adipiscing platea.',
                      nodeType: 'text',
                    },
                  ],
                  nodeType: 'paragraph',
                },
              ],
              nodeType: 'document',
            },
            body: {
              sys: {
                type: 'Link',
                linkType: 'Entry',
                id: '0r6rf4ALDvSYCbWF9gG2W',
              },
            },
            form: {
              sys: {
                type: 'Link',
                linkType: 'Entry',
                id: '2earrkEFekIVqpWE4h4gMu',
              },
            },
          },
        },
      ],
    },
  },
}

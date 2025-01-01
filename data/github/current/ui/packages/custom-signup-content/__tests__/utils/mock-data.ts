import {BLOCKS} from '@contentful/rich-text-types'
import type {CustomSignupContentProps} from '../../CustomSignupContent'
import type {ContentSchema} from '../../lib/types/contentful/content-schema'
import type {EntrySchema} from '../../lib/types/contentful/entry-schema'

export function getCustomSignupContentProps(): CustomSignupContentProps {
  return {
    contentfulContent: {
      entry: entryJSON,
      content_entries: contentJSON,
      assets: [],
    },
  }
}

export function getCustomSignupContentPropsNoContentEntries(): CustomSignupContentProps {
  return {
    contentfulContent: {
      entry: entryJSON,
      content_entries: [],
      assets: [],
    },
  }
}

export const entryJSON: EntrySchema = {
  sys: {
    id: 'signupCopilotBusinessVariation',
    contentType: {
      sys: {
        id: 'content',
      },
    },
  },
  fields: {
    title: '/signup Copilot Business variation',
    id: 'signupCopilotBusinessVariation',
    htmlId: 'copilot-business',
    heading: 'Lets get you started with Copilot Business',
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
              value:
                "Copilot Business is available for organizations and enterprises that want control over Copilot policies, including which members can use Copilot. To begin using it, you'll need two things:",
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
                        'A personal user account\nEvery person who uses GitHub signs in to a user account, which will be your identity on GitHub.',
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
                        'An organization or enterprise account\nOrganizations are shared accounts where a large number of people can collaborate across many projects at once. Enterprises allow administrators to centrally manage policy and billing for multiple organizations.',
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
              value: "We'll hope you get started with both. Let's start by creating your personal user account.",
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
}

export const contentJSON: ContentSchema[] = [
  {
    sys: {
      id: '',
      contentType: {
        sys: {
          id: 'content',
        },
      },
    },
    fields: {
      title: '/signup Bullet style checked',
      id: 'bulletStyleChecked',
      htmlId: 'bullet-style-checked',
      heading: '',
      text: {
        nodeType: BLOCKS.DOCUMENT,
        data: {},
        content: [],
      },
    },
  },
  {
    sys: {
      id: '',
      contentType: {
        sys: {
          id: 'content',
        },
      },
    },
    fields: {
      title: '/signup Pill Optional',
      id: '',
      htmlId: 'signup-pill',
      heading: 'Optional',
      text: {
        nodeType: BLOCKS.DOCUMENT,
        data: {},
        content: [],
      },
    },
  },
]

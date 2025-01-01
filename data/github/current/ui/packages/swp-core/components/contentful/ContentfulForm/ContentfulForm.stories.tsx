import '@primer/react-brand/lib/css/main.css'

import type {Meta, StoryObj} from '@storybook/react'

import {ContentfulForm} from './ContentfulForm'
import {BLOCKS} from '@contentful/rich-text-types'

const meta: Meta<typeof ContentfulForm> = {
  title: 'Mkt/Swp/Contentful/ContentfulForm',
  component: ContentfulForm,
}

export default meta

type Story = StoryObj<typeof ContentfulForm>

const onSubmit = async (data: unknown) => {
  // eslint-disable-next-line no-console
  console.log(data)
}

export const Default: Story = {
  args: {
    component: {
      sys: {
        contentType: {
          sys: {
            id: 'form',
          },
        },
        id: 'form',
      },
      fields: {
        heading: {
          data: {},
          content: [
            {
              data: {},
              content: [
                {
                  data: {},
                  marks: [],
                  value: 'Talk to our sales team',
                  nodeType: 'text',
                },
              ],
              nodeType: BLOCKS.PARAGRAPH,
            },
          ],
          nodeType: BLOCKS.DOCUMENT,
        },
        campaign: {
          sys: {
            contentType: {
              sys: {
                id: 'marketoCampaign',
              },
            },
            id: '',
          },
          fields: {
            cDLProgramName: 'GitHub',
            sFDCLastCampaignStatus: 'Responded',
            source: 'Contact Sales',
            extraFormAttributes: {
              salesforceId: 'contact-sales',
            },
          },
        },
        layout: {
          sys: {
            contentType: {
              sys: {
                id: 'formLayout',
              },
            },
            id: '',
          },
          fields: {
            formFields: [
              {
                sys: {
                  contentType: {
                    sys: {
                      id: 'formFieldTextInput',
                    },
                  },
                  id: '',
                },
                fields: {
                  htmlName: 'emailAddress',
                  label: 'Your email',
                  placeholder: 'you@email.com',
                  type: 'email',
                  validations: [
                    {
                      sys: {
                        contentType: {
                          sys: {
                            id: 'formFieldValidation',
                          },
                        },
                        id: '',
                      },
                      fields: {
                        name: 'REQUIRED',
                      },
                    },
                    {
                      sys: {
                        contentType: {
                          sys: {
                            id: 'formFieldValidation',
                          },
                        },
                        id: '',
                      },
                      fields: {
                        name: 'WORK_EMAIL_ONLY',
                      },
                    },
                  ],
                },
              },
            ],
          },
        },
        submitText: 'Contact Sales',
      },
    },

    onSubmit,
  },
}

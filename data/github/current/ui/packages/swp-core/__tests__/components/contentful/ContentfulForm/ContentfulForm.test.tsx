import {BLOCKS} from '@contentful/rich-text-types'
import {screen} from '@testing-library/react'

import {render} from '@github-ui/react-core/test-utils'

import {ContentfulForm} from '../../../../components/contentful/ContentfulForm/ContentfulForm'
import type {Form} from '../../../../schemas/contentful/contentTypes/form'

const component: Form = {
  sys: {
    contentType: {
      sys: {
        id: 'form',
      },
    },
    id: '',
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
            },
          },
          {
            sys: {
              contentType: {
                sys: {
                  id: 'formFieldTextArea',
                },
              },
              id: '',
            },
            fields: {
              htmlName: 'message',
              label: 'Message',
              placeholder: 'Describe your project',
            },
          },
        ],
      },
    },
    submitText: 'Contact Sales',
  },
}

describe('ContentfulForm', () => {
  it('renders the form with the right layout', async () => {
    render(<ContentfulForm component={component} />)

    expect(screen.getByLabelText(/Your email/)).toBeInTheDocument()
    expect(screen.getByLabelText(/Message/)).toBeInTheDocument()
  })

  it('verifies the email format', async () => {
    const {user} = render(<ContentfulForm component={component} />)

    const emailInput = screen.getByLabelText(/Your email/)

    await user.type(emailInput, 'not-an-email')
    await user.click(screen.getByText(/Contact Sales/))

    await expect(screen.findByText(/Please enter a valid email address/)).resolves.toBeInTheDocument()
  })

  it('submits if everything is correct', async () => {
    const spy = jest.fn()

    const {user} = render(<ContentfulForm component={component} onSubmit={spy} skipOctocaptcha />)

    const emailInput = screen.getByLabelText(/Your email/)
    const messageInput = screen.getByLabelText(/Message/)

    await user.type(emailInput, 'name@example.com')
    await user.type(messageInput, 'This is a message')
    await user.click(screen.getByText(/Contact Sales/))

    expect(spy).toHaveBeenCalledTimes(1)
  })

  it('does not complain about missing optional fields', async () => {
    const spy = jest.fn()

    const {user} = render(<ContentfulForm component={component} onSubmit={spy} skipOctocaptcha />)

    await user.click(screen.getByText(/Contact Sales/))

    expect(spy).toHaveBeenCalledTimes(1)
  })

  describe('handling Octocaptcha', () => {
    it('shows a validation message if the Octocaptcha is not completed', async () => {
      const {user} = render(<ContentfulForm component={component} onSubmit={jest.fn()} />)

      await user.click(screen.getByText(/Contact Sales/))

      await expect(screen.findByText(/Please complete the CAPTCHA/)).resolves.toBeInTheDocument()
    })
  })
})

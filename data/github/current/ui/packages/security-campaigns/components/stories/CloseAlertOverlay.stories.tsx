import {disableA11yRuleForDialog} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'
import {CloseAlertOverlay, type CloseAlertOverlayProps} from '../CloseAlertOverlay'
import {HttpResponse, delay, http} from 'msw'
import {createRepository} from '../../test-utils/mock-data'

const meta = {
  title: 'Apps/Security Campaigns/CloseAlertOverlay',
  component: CloseAlertOverlay,
  parameters: {
    a11y: disableA11yRuleForDialog,
    msw: {
      handlers: [
        http.post('/github/security-campaigns/security/campaigns/5/alerts', async () => {
          await delay(1000)

          return HttpResponse.json(
            {message: 'Something went wrong'},
            {
              status: 400,
            },
          )
        }),
      ],
    },
  },
} satisfies Meta<typeof CloseAlertOverlay>

export default meta
type Story = StoryObj<typeof CloseAlertOverlay>

export const OneAlert: Story = {
  name: 'One alert',
  render: (args: CloseAlertOverlayProps) => <CloseAlertOverlay {...args} />,
  args: {
    setOpen: () => undefined,
    repository: createRepository(),
    securityCampaignNumber: 5,
    alertNumbers: [1],
    delegatedAlertDismissalEnabled: false,
  },
}

export const MultipleAlerts: Story = {
  name: 'Multiple alerts',
  render: (args: CloseAlertOverlayProps) => <CloseAlertOverlay {...args} />,
  args: {
    setOpen: () => undefined,
    repository: createRepository(),
    securityCampaignNumber: 5,
    alertNumbers: [1, 2, 3],
    delegatedAlertDismissalEnabled: false,
  },
}

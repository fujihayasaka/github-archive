import {screen, within} from '@testing-library/react'
import {ListView} from '@github-ui/list-view'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {createSecurityCampaignAlert, getAssignee} from '../../test-utils/mock-data'
import {SecuritySeverity, type SecurityCampaignAlert} from '../../types/security-campaign-alert'
import {AlertListItem, type AlertListItemProps} from '../../components/AlertListItem'

// A ListItem can only be rendered within a ListView, so we'll need to create a wrapper component
const Wrapper = ({children}: {children?: React.ReactNode}) => (
  <ListView isSelectable title="">
    {children}
  </ListView>
)
const render = (props?: Partial<AlertListItemProps>) =>
  reactRender(<AlertListItem alert={alert} isSelected={false} onSelect={jest.fn()} {...props} />, {
    wrapper: Wrapper,
  })

const alert = createSecurityCampaignAlert({
  number: 125,
  title: 'Code injection',
  securitySeverity: SecuritySeverity.Medium,
  truncatedPath: 'app/controllers/application_controller.r...',
  startLine: 27,
  createdAt: '2024-05-22T13:20:25.947Z',
})

const fixedAlert: SecurityCampaignAlert = {
  ...alert,
  isFixed: true,
  fixedAt: '2024-05-23T13:20:25.947Z',
}

const falsePositiveAlert: SecurityCampaignAlert = {
  ...alert,
  isDismissed: true,
  dismissedAt: '2024-05-24T13:20:25.947Z',
  resolution: 'FALSE_POSITIVE',
}

const wontFixAlert: SecurityCampaignAlert = {
  ...alert,
  isDismissed: true,
  dismissedAt: '2024-05-25T13:20:25.947Z',
  resolution: 'WONT_FIX',
}

const usedInTestsAlert: SecurityCampaignAlert = {
  ...alert,
  isDismissed: true,
  dismissedAt: '2024-05-26T13:20:25.947Z',
  resolution: 'USED_IN_TESTS',
}

it('renders an open alert', () => {
  render()
  const listItem = within(screen.getByRole('listitem'))
  expect(listItem.getByRole('heading')).toHaveTextContent('Code injection')
  expect(listItem.getByRole('link')).toHaveTextContent('Code injection')
  expect(listItem.getByRole('link')).toHaveAttribute('href', '/github/security-campaigns/security/code-scanning/125')
  expect(listItem.getByTestId('list-view-item-main-content')).toHaveTextContent(
    '#125 · Opened May 22, 2024 · Detected by CodeQL in app/controllers/application_controller.r...:27',
  )
  expect(listItem.getByText('Status: Open.')).toBeInTheDocument()
})

it('renders a fixed alert', () => {
  render({alert: fixedAlert})
  const listItem = within(screen.getByRole('listitem'))
  expect(listItem.getByRole('heading')).toHaveTextContent('Code injection')
  expect(listItem.getByRole('link')).toHaveTextContent('Code injection')
  expect(listItem.getByRole('link')).toHaveAttribute('href', '/github/security-campaigns/security/code-scanning/125')
  expect(listItem.getByTestId('list-view-item-main-content')).toHaveTextContent(
    '#125 · Closed as fixed May 23, 2024 · Detected by CodeQL in app/controllers/application_controller.r...:27',
  )
  expect(listItem.getByText('Status: Fixed.')).toBeInTheDocument()
})

it('renders a false positive alert', () => {
  render({alert: falsePositiveAlert})
  const listItem = within(screen.getByRole('listitem'))
  expect(listItem.getByRole('heading')).toHaveTextContent('Code injection')
  expect(listItem.getByRole('link')).toHaveTextContent('Code injection')
  expect(listItem.getByRole('link')).toHaveAttribute('href', '/github/security-campaigns/security/code-scanning/125')
  expect(listItem.getByTestId('list-view-item-main-content')).toHaveTextContent(
    '#125 · Closed as false positive May 24, 2024 · Detected by CodeQL in app/controllers/application_controller.r...:27',
  )
  expect(listItem.getByText('Status: Dismissed.')).toBeInTheDocument()
})

it("renders a won't fix alert", () => {
  render({alert: wontFixAlert})
  const listItem = within(screen.getByRole('listitem'))
  expect(listItem.getByRole('heading')).toHaveTextContent('Code injection')
  expect(listItem.getByRole('link')).toHaveTextContent('Code injection')
  expect(listItem.getByRole('link')).toHaveAttribute('href', '/github/security-campaigns/security/code-scanning/125')
  expect(listItem.getByTestId('list-view-item-main-content')).toHaveTextContent(
    "#125 · Closed as won't fix May 25, 2024 · Detected by CodeQL in app/controllers/application_controller.r...:27",
  )
  expect(listItem.getByText('Status: Dismissed.')).toBeInTheDocument()
})

it('renders a used in tests alert', () => {
  render({alert: usedInTestsAlert})
  const listItem = within(screen.getByRole('listitem'))
  expect(listItem.getByRole('heading')).toHaveTextContent('Code injection')
  expect(listItem.getByRole('link')).toHaveTextContent('Code injection')
  expect(listItem.getByRole('link')).toHaveAttribute('href', '/github/security-campaigns/security/code-scanning/125')
  expect(listItem.getByTestId('list-view-item-main-content')).toHaveTextContent(
    '#125 · Closed as used in tests May 26, 2024 · Detected by CodeQL in app/controllers/application_controller.r...:27',
  )
  expect(listItem.getByText('Status: Dismissed.')).toBeInTheDocument()
})

it('renders a fixed and dismissed alert', () => {
  render({
    alert: {...fixedAlert, isDismissed: true, dismissedAt: '2024-05-24T13:20:25.947Z', resolution: 'FALSE_POSITIVE'},
  })
  const listItem = within(screen.getByRole('listitem'))
  expect(listItem.getByRole('heading')).toHaveTextContent('Code injection')
  expect(listItem.getByRole('link')).toHaveTextContent('Code injection')
  expect(listItem.getByRole('link')).toHaveAttribute('href', '/github/security-campaigns/security/code-scanning/125')
  expect(listItem.getByTestId('list-view-item-main-content')).toHaveTextContent(
    '#125 · Closed as false positive May 24, 2024 · Detected by CodeQL in app/controllers/application_controller.r...:27',
  )
  expect(listItem.getByText('Status: Dismissed.')).toBeInTheDocument()
})

it('renders the repo link when repo parent link is set', () => {
  render({alertParentLink: {kind: 'repository'}, alert})
  expect(within(screen.getByRole('listitem')).getByText('security-campaigns')).toHaveAttribute(
    'href',
    '/github/security-campaigns',
  )
})

it('renders the campaign link when campaign parent link is set', () => {
  render({alertParentLink: {kind: 'campaign', campaignNumber: 1}, alert})
  expect(within(screen.getByRole('listitem')).getByText('security-campaigns')).toHaveAttribute(
    'href',
    '/github/security-campaigns/security/campaigns/1',
  )
})

it('renders the status for dismissed alerts', () => {
  render({alert: {...alert, isDismissed: true}})
  expect(screen.getByText('Status: Dismissed.')).toBeInTheDocument()
})

it('renders the status for fixed alerts', () => {
  render({alert: {...alert, isFixed: true}})
  expect(screen.getByText('Status: Fixed.')).toBeInTheDocument()
})

it('renders the status for dismissed and fixed alerts', () => {
  render({alert: {...alert, isDismissed: true, isFixed: true}})
  expect(screen.getByText('Status: Dismissed.')).toBeInTheDocument()
})

it('renders the severity label for medium severity', () => {
  render()
  expect(screen.getByText('Medium')).toBeInTheDocument()
})

it('renders the severity label for critical severity', () => {
  render({alert: {...alert, securitySeverity: SecuritySeverity.Critical}})
  expect(screen.getByText('Critical')).toBeInTheDocument()
})

it('does not render the autofix label when no suggested fix is available', () => {
  render()
  expect(screen.queryByText('Autofix')).not.toBeInTheDocument()
})

it('renders the autofix label when a suggested fix is available', () => {
  render({alert: {...alert, hasSuggestedFix: true}})
  expect(screen.getByText('Autofix')).toBeInTheDocument()
})

it('renders assignees', () => {
  render({alert: {...alert, assignees: [getAssignee()]}})
  expect(
    screen.getByRole('img', {
      name: 'monalisa',
    }),
  ).toBeInTheDocument()
})

it('fires given onSelect handler when checking checkbox', async () => {
  const onSelect = jest.fn()

  const {user} = render({isSelected: false, onSelect})

  expect(onSelect).not.toHaveBeenCalled()

  const checkbox = screen.getByRole('checkbox')

  await user.click(checkbox)

  expect(onSelect).toHaveBeenCalledTimes(1)
  expect(onSelect).toHaveBeenCalledWith(true)
})

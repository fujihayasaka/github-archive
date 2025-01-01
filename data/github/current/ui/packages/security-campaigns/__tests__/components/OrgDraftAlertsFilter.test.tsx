import {setupExpectedAsyncErrorHandler} from '@github-ui/filter/test-utils'
import {OrgDraftAlertsFilter, type OrgDraftAlertsFilterProps} from '../../components/OrgDraftAlertsFilter'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {getSecurityCampaign} from '@github-ui/security-campaigns-shared/test-utils/mock-data'
import {mockFetch} from '@github-ui/mock-fetch'
import {StateFilterProvider} from '@github-ui/filter/providers'

beforeEach(() => {
  setupExpectedAsyncErrorHandler()
})

const defaultProps: OrgDraftAlertsFilterProps = {
  providers: [new StateFilterProvider()],
  query: 'is:open',
  setQuery: jest.fn(),
  campaign: getSecurityCampaign(),
  setCampaign: jest.fn(),
  organizationLogin: 'github',
}

const render = (props?: Partial<OrgDraftAlertsFilterProps>) =>
  reactRender(<OrgDraftAlertsFilter {...defaultProps} {...props} />)

test('Renders the correct query', async () => {
  render({
    query: 'is:open repo:test-repo',
  })

  const filterInput = screen.getByRole('combobox', {name: 'Filter'})
  expect(filterInput).toHaveValue('is:open repo:test-repo')
})

test('Discards the changes when the discard button is clicked', async () => {
  const campaign = getSecurityCampaign({creationQuery: 'is:open repo:test-repo'})
  const {user} = render({
    query: 'is:open repo:test-repo',
    campaign,
  })

  const filterInput = screen.getByRole('combobox', {name: 'Filter'})
  await user.click(filterInput)
  await user.paste('tool:codeql')
  await user.click(screen.getByRole('button', {name: 'Discard'}))

  expect(filterInput).toHaveValue('is:open repo:test-repo')
})

test('Saves the changes when the save button is clicked', async () => {
  const route = mockFetch.mockRoute(
    `/orgs/github/security/campaigns/drafts/${defaultProps.campaign.number}`,
    {},
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render()

  await user.click(screen.getByRole('combobox', {name: 'Filter'}))
  await user.paste(' tool:codeql')
  await user.click(screen.getByRole('button', {name: 'Save'}))

  expect(route).toHaveBeenCalledWith(
    expect.any(String),
    expect.objectContaining({
      method: 'put',
      body: JSON.stringify({
        campaign_name: defaultProps.campaign.name,
        campaign_description: defaultProps.campaign.description,
        campaign_due_date: undefined,
        campaign_managers: defaultProps.campaign.managers.map(manager => manager.id),
        team_managers: defaultProps.campaign.teamManagers.map(team => team.id),
        campaign_contact_link: defaultProps.campaign.contactLink,
        query: 'is:open tool:codeql',
      }),
    }),
  )
  expect(defaultProps.setCampaign).toHaveBeenCalledWith(
    expect.objectContaining({
      creationQuery: 'is:open tool:codeql',
    }),
  )
})

test('Shows an error message when the save fails', async () => {
  mockFetch.mockRoute(
    `/orgs/github/security/campaigns/drafts/${defaultProps.campaign.number}`,
    {message: 'This is a test error message'},
    {
      ok: false,
      status: 500,
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render()

  await user.click(screen.getByRole('combobox', {name: 'Filter'}))
  await user.paste(' tool:codeql')
  await user.click(screen.getByRole('button', {name: 'Save'}))

  const errorMessage = await screen.findByText('This is a test error message')
  expect(errorMessage).toBeInTheDocument()
})

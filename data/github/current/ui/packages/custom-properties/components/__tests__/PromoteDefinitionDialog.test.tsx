import {expectMockFetchCalledTimes, mockFetch} from '@github-ui/mock-fetch'
import {screen, waitFor} from '@testing-library/react'

import {renderBusinessOrgPropertyDefinitionDetailsComponent} from '../../test-utils/Render'
import {PromoteDefinitionDialog} from '../PromoteDefinitionDialog'

const sampleProps: React.ComponentProps<typeof PromoteDefinitionDialog> = {
  business: {
    name: 'MegaCorp.',
    slug: 'mega-corp',
  },
  definition: {
    propertyName: 'environment',
    valueType: 'string',
    required: false,
    defaultValue: null,
    description: null,
    allowedValues: null,
    valuesEditableBy: 'org_actors',
    regex: null,
    source: {
      type: 'org',
      name: 'Acme',
      slug: 'acme',
      avatarUrl: '',
    },
  },
  onCancel: jest.fn(),
  onDismiss: jest.fn(),
}

const navigateFn = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => navigateFn,
  }
})

beforeEach(navigateFn.mockClear)

const expectedPromotePath = '/enterprises/mega-corp/settings/custom-property/organizations/acme/environment/promote'

describe('PromoteDefinitionDialog', () => {
  it('promotes definition', async () => {
    const {user} = renderBusinessOrgPropertyDefinitionDetailsComponent(<PromoteDefinitionDialog {...sampleProps} />)

    mockFetch.mockRoute('/sessions/in_sudo', undefined, {ok: true, text: async () => 'true'})
    mockFetch.mockRouteOnce(expectedPromotePath)

    await user.click(screen.getByText('Promote'))

    expectMockFetchCalledTimes('/sessions/in_sudo', 1)
    await waitFor(() => expectMockFetchCalledTimes(expectedPromotePath, 1))

    expect(navigateFn).toHaveBeenCalledWith('/enterprises/mega-corp/settings/custom-property/environment')
  })

  it('shows flash banner if request fails', async () => {
    const {user} = renderBusinessOrgPropertyDefinitionDetailsComponent(<PromoteDefinitionDialog {...sampleProps} />)

    mockFetch.mockRoute('/sessions/in_sudo', undefined, {ok: true, text: async () => 'true'})
    const routeMock = mockFetch.mockRouteOnce(expectedPromotePath, undefined, {
      ok: false,
      json: async () => ({
        error: 'Displayed server error',
      }),
    })

    await user.click(screen.getByText('Promote'))

    await waitFor(() => expect(routeMock).toHaveBeenCalled())
    await screen.findByTestId('server-error-banner')
    await screen.findByText('Displayed server error')
    expect(navigateFn).not.toHaveBeenCalled()
  })

  it('hides dialog while the request is in flight', async () => {
    const {user} = renderBusinessOrgPropertyDefinitionDetailsComponent(<PromoteDefinitionDialog {...sampleProps} />)

    mockFetch.mockRoute('/sessions/in_sudo', undefined, {ok: true, text: async () => 'true'})
    mockFetch.mockRoute(expectedPromotePath)

    await user.click(screen.getByText('Promote'))

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()

    await waitFor(() => expect(navigateFn).toHaveBeenCalled())
    expectMockFetchCalledTimes(expectedPromotePath, 1)
  })
})

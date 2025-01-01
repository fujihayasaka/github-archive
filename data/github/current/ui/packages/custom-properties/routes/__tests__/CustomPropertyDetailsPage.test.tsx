import type {CustomPropertyDetailsPagePayload, PropertyDefinition} from '@github-ui/custom-properties-types'
import {expectMockFetchCalledWith, mockFetch} from '@github-ui/mock-fetch'
import {screen, waitFor, within} from '@testing-library/react'

import {sampleBusinessSource, sampleOrgSource} from '../../test-utils/mock-data'
import {
  renderBusinessOrgPropertyDefinitionDetailsComponent,
  renderPropertyDefinitionsComponent,
} from '../../test-utils/Render'
import {CustomPropertyDetailsPage} from '../CustomPropertyDetailsPage'

const navigateFn = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => navigateFn,
  }
})

beforeEach(navigateFn.mockClear)

const definition: PropertyDefinition = {
  propertyName: 'env',
  valueType: 'string',
  required: false,
  defaultValue: null,
  description: null,
  allowedValues: null,
  valuesEditableBy: 'org_actors',
  regex: null,
  source: sampleOrgSource,
}

const routePayload: CustomPropertyDetailsPagePayload = {
  definition,
  propertyNames: [],
  business: {name: 'Acme', slug: 'acme'},
  canManageProperty: false,
}

describe('CustomPropertyDetailsPage', () => {
  // Copied from https://github.com/primer/react/blob/main/packages/react/src/Banner/Banner.test.tsx:
  beforeEach(() => {
    // Note: this error occurs due to our usage of `@container` within a
    // `<style>` tag in Banner. The CSS parser for jsdom does not support this
    // syntax and will fail with an error containing the message below.
    // eslint-disable-next-line no-console
    const originalConsoleError = console.error
    jest.spyOn(console, 'error').mockImplementation((value, ...args) => {
      if (!value?.message?.includes('Could not parse CSS stylesheet')) {
        originalConsoleError(value, ...args)
      }
    })
  })

  it('renders correctly', async () => {
    const {user} = renderPropertyDefinitionsComponent(<CustomPropertyDetailsPage />, {routePayload})

    expect(screen.getByTestId('readonly-property-definitions-settings')).toBeInTheDocument()

    const editButton = screen.getByRole('button', {name: 'Edit'})
    expect(editButton).toBeInTheDocument()
    await user.click(editButton)

    expect(screen.getByTestId('settings-page-content')).toBeInTheDocument()
  })

  it('renders the danger zone and the delete dialog', async () => {
    const {user} = renderPropertyDefinitionsComponent(<CustomPropertyDetailsPage />, {routePayload})

    expect(screen.getByTestId('readonly-property-definitions-settings')).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Edit'})).toBeInTheDocument()

    expect(screen.getByRole('heading', {name: 'Additional options'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {name: 'Delete property'})).toBeInTheDocument()
    expect(screen.queryByRole('heading', {name: 'Promote to enterprise'})).not.toBeInTheDocument()

    const deleteButton = screen.getByRole('button', {name: 'Delete property'})
    await user.click(deleteButton)

    await user.click(within(screen.getByRole('dialog')).getByLabelText('Close'))

    expect(deleteButton).toHaveFocus()
  })

  it('renders the danger zone and the promotion dialog', async () => {
    const payload: CustomPropertyDetailsPagePayload = {
      ...routePayload,
      business: {
        name: 'MegaCorp.',
        slug: 'mega-corp',
      },
      definition: {
        ...definition,
        source: {
          type: 'org',
          name: 'Acme',
          slug: 'acme',
          avatarUrl: '',
        },
      },
    }
    renderBusinessOrgPropertyDefinitionDetailsComponent(<CustomPropertyDetailsPage />, {
      routePayload: payload,
      appPayload: {
        ['enabled_features']: {['enterprise_custom_properties_promotion']: true},
      },
    })

    expect(screen.getByTestId('readonly-property-definitions-settings')).toBeInTheDocument()

    expect(screen.getByRole('heading', {name: 'Additional options'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {name: 'Promote to enterprise'})).toBeInTheDocument()
    expect(screen.queryByRole('heading', {name: 'Delete property'})).not.toBeInTheDocument()
  })

  it('opens orgs conflicts dialog when user tries to promote property with duplicates across enterprise', async () => {
    const payload: CustomPropertyDetailsPagePayload = {
      ...routePayload,
      business: {
        name: 'MegaCorp.',
        slug: 'mega-corp',
      },
      definition: {
        ...definition,
        source: {
          type: 'org',
          name: 'Acme',
          slug: 'acme',
          avatarUrl: '',
        },
      },
      orgConflicts: {
        usages: [{name: 'another-org', avatarUrl: 'avatar2.com', propertyType: 'string'}],
        totalUsageCount: 100,
      },
    }
    const {user} = renderBusinessOrgPropertyDefinitionDetailsComponent(<CustomPropertyDetailsPage />, {
      routePayload: payload,
      appPayload: {
        ['enabled_features']: {['enterprise_custom_properties_promotion']: true},
      },
    })

    expect(screen.getByTestId('readonly-property-definitions-settings')).toBeInTheDocument()

    await user.click(screen.getByRole('button', {name: 'Promote to enterprise'}))
    const dialog = screen.getByRole('dialog')

    expect(
      within(dialog).getByText(
        'This property cannot be promoted to MegaCorp. because there are conflicting properties (showing 1 out of a total 100 conflicts).',
        {exact: false},
      ),
    ).toBeInTheDocument()
  })

  it('renders readonly page for org property in business UI', async () => {
    const payload: CustomPropertyDetailsPagePayload = {
      ...routePayload,
      canManageProperty: true,
    }

    renderBusinessOrgPropertyDefinitionDetailsComponent(<CustomPropertyDetailsPage />, {
      routePayload: payload,
    })

    const manageLink = screen.getAllByRole('link', {name: 'Manage in organization'})[0] as HTMLAnchorElement
    expect(manageLink).toHaveAttribute('href', '/organizations/github/settings/custom-property/env')
    expect(
      screen.getByText(`This property is managed by ${sampleOrgSource.name} and can't be edited here.`),
    ).toBeInTheDocument()

    expect(screen.getByTestId('readonly-property-definitions-settings')).toBeInTheDocument()
    expect(screen.queryByRole('link', {name: 'View in Enterprise settings'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Edit'})).not.toBeInTheDocument()
  })

  it('renders readonly page for business property in org UI and hides danger zone', async () => {
    // Note: this error occurs because of the Banner component that is added to
    // the UI due to the `business` prop in the mock payload. The CSS parser for
    // jsdom does not support some of the styling syntax for Banner and will fail
    // with an error containing the message below.
    // Tracking issue: https://github.com/github/primer/issues/3882
    // eslint-disable-next-line no-console
    const originalConsoleError = console.error
    jest.spyOn(console, 'error').mockImplementation((value, ...args) => {
      if (!value?.message?.includes('Could not parse CSS stylesheet')) {
        originalConsoleError(value, ...args)
      }
    })

    const payload: CustomPropertyDetailsPagePayload = {
      ...routePayload,
      definition: {...routePayload.definition!, source: sampleBusinessSource},
      canManageProperty: true,
    }

    renderPropertyDefinitionsComponent(<CustomPropertyDetailsPage />, {
      routePayload: payload,
    })

    const managedLinks = screen.queryAllByRole('link', {name: 'Manage in enterprise', hidden: true})
    expect(managedLinks.length).toBe(2)

    expect(managedLinks[0]).toHaveAttribute('href', '/enterprises/gitco/settings/custom-property/env')
    expect(
      screen.getByText(`This property is managed by ${sampleBusinessSource.name} and can't be edited here.`),
    ).toBeInTheDocument()

    expect(screen.getByTestId('readonly-property-definitions-settings')).toBeInTheDocument()

    expect(screen.queryByRole('button', {name: 'Edit'})).not.toBeInTheDocument()
    expect(screen.queryByRole('heading', {name: 'Additional options'})).not.toBeInTheDocument()
  })

  it('shows validation error on save if allowed values are empty and focuses the field', async () => {
    const {user} = renderPropertyDefinitionsComponent(<CustomPropertyDetailsPage />, {
      routePayload: {...routePayload, definition: undefined},
    })
    await user.type(screen.getByLabelText('Name*'), 'env')

    await user.click(screen.getByRole('button', {name: 'Type: Text'}))
    await user.click(screen.getByText('Single select'))

    await user.click(screen.getByText('Save property'))
    const banner = await screen.findByTestId('server-error-banner')

    expect(banner).toHaveFocus()

    expect(screen.getByRole('link', {name: 'add an option'})).toHaveAttribute('href', '#option-input')
    expect(screen.getByRole('link', {name: 'change the property type'})).toHaveAttribute(
      'href',
      '#type-dropdown-button',
    )
  })

  it('shows generic flash banner if request fails with no error property', async () => {
    const {user} = renderPropertyDefinitionsComponent(<CustomPropertyDetailsPage />, {routePayload})

    mockFetch.mockRoute('/sessions/in_sudo', undefined, {ok: true, text: async () => 'true'})
    const routeMock = mockFetch.mockRouteOnce('/organizations/acme/settings/custom-properties', undefined, {
      ok: false,
    })

    await user.click(screen.getByRole('button', {name: 'Edit'}))

    await user.type(screen.getByLabelText('Name*'), 'environment')
    await user.click(screen.getByText('Save property'))

    await waitFor(() => expect(routeMock).toHaveBeenCalled())

    const serverErrorBanner = await screen.findByTestId('server-error-banner')
    expect(within(serverErrorBanner).getByText('Something went wrong.')).toBeInTheDocument()
    expect(navigateFn).not.toHaveBeenCalled()
  })

  it('shows error message from server', async () => {
    const {user} = renderPropertyDefinitionsComponent(<CustomPropertyDetailsPage />, {routePayload})

    mockFetch.mockRoute('/sessions/in_sudo', undefined, {ok: true, text: async () => 'true'})
    const routeMock = mockFetch.mockRouteOnce(
      '/organizations/acme/settings/custom-properties',
      {
        error: 'Could not save properties because reasons',
      },
      {
        ok: false,
      },
    )

    await user.click(screen.getByRole('button', {name: 'Edit'}))

    await user.type(screen.getByLabelText('Name*'), 'environment')
    await user.click(screen.getByText('Save property'))

    await waitFor(() => expect(routeMock).toHaveBeenCalled())

    const serverErrorBanner = await screen.findByTestId('server-error-banner')
    expect(within(serverErrorBanner).getByText('Could not save properties because reasons')).toBeInTheDocument()
    expect(navigateFn).not.toHaveBeenCalled()
  })

  it('returns to readonly mode on edit complete', async () => {
    const {user} = renderPropertyDefinitionsComponent(<CustomPropertyDetailsPage />, {
      routePayload,
      appPayload: {
        ['enabled_features']: {
          ['enterprise_custom_properties_list']: true,
        },
      },
    })

    mockFetch.mockRoute('/sessions/in_sudo', undefined, {ok: true, text: async () => 'true'})
    mockFetch.mockRouteOnce('/organizations/acme/settings/custom-properties')

    expect(screen.getByTestId('readonly-property-definitions-settings')).toBeInTheDocument()
    await user.click(screen.getByRole('button', {name: 'Edit'}))

    await user.type(screen.getByLabelText('Description'), 'Update')
    await user.click(screen.getByText('Save property'))

    await waitFor(() =>
      expectMockFetchCalledWith('/organizations/acme/settings/custom-properties', {
        propertyName: 'env',
        valueType: 'string',
        required: false,
        defaultValue: null,
        description: 'Update',
        allowedValues: null,
      }),
    )

    expect(navigateFn).toHaveBeenCalledWith('/organizations/acme/settings/custom-property/env')
    expect(screen.getByTestId('readonly-property-definitions-settings')).toBeInTheDocument()
  })

  it('returns to readonly mode on edit cancel', async () => {
    const {user} = renderPropertyDefinitionsComponent(<CustomPropertyDetailsPage />, {
      routePayload,
      appPayload: {
        ['enabled_features']: {
          ['enterprise_custom_properties_list']: true,
        },
      },
    })

    expect(screen.getByTestId('readonly-property-definitions-settings')).toBeInTheDocument()
    await user.click(screen.getByRole('button', {name: 'Edit'}))

    await user.click(screen.getByText('Cancel'))

    expect(screen.getByTestId('readonly-property-definitions-settings')).toBeInTheDocument()
  })

  it('returns to readonly mode on create complete', async () => {
    const {user} = renderPropertyDefinitionsComponent(<CustomPropertyDetailsPage />, {
      routePayload: {...routePayload, definition: undefined},
      appPayload: {
        ['enabled_features']: {
          ['enterprise_custom_properties_list']: true,
        },
      },
    })

    mockFetch.mockRoute('/sessions/in_sudo', undefined, {ok: true, text: async () => 'true'})
    mockFetch.mockRouteOnce('/organizations/acme/settings/custom-properties')

    await user.type(screen.getByLabelText('Name*'), 'environment')
    await user.click(screen.getByText('Save property'))

    await waitFor(() =>
      expectMockFetchCalledWith('/organizations/acme/settings/custom-properties', {
        propertyName: 'environment',
        valueType: 'string',
        required: false,
        defaultValue: null,
        description: null,
        allowedValues: null,
      }),
    )

    expect(navigateFn).toHaveBeenCalledWith('/organizations/acme/settings/custom-property/environment')
  })

  it('returns to the list on create cancel', async () => {
    const {user} = renderPropertyDefinitionsComponent(<CustomPropertyDetailsPage />, {
      routePayload: {...routePayload, definition: undefined},
      appPayload: {
        ['enabled_features']: {
          ['enterprise_custom_properties_list']: true,
        },
      },
    })

    await user.click(screen.getByText('Cancel'))
    expect(navigateFn).toHaveBeenCalledWith('/organizations/acme/settings/custom-properties')
  })
})

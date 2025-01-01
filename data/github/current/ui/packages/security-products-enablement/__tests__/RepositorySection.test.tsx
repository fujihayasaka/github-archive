import {screen, within, waitFor} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {
  createRepos,
  getOrganizationSettingsSecurityProductsRoutePayload,
  getUnbundledOrganizationSettingsSecurityProductsRoutePayload,
  searchResults,
} from '../test-utils/mock-data'
import {expectMockFetchCalledTimes, expectMockFetchCalledWith, mockFetch} from '@github-ui/mock-fetch'
import {setupExpectedAsyncErrorHandler, updateFilterValue} from '@github-ui/filter/test-utils'
import {dialogRepositoryWrapper as wrapper, customRepositorySection} from './test-helpers'
import {SecurityProductAvailability} from '../security-products-enablement-types'
import {swallowCSSParsingError} from '../test-utils/test-helper'

jest.setTimeout(4_500)

describe('RepositorySection', () => {
  beforeEach(() => {
    swallowCSSParsingError()
    jest.spyOn(console, 'error').mockImplementation((message: string) => {
      // * Because Filter is asynchronous, there are console errors that are thrown, but expected. This will rethrow
      // * any errors that are not related to the async nature of the component.
      if (!message.includes?.('wrapped in act(')) {
        // eslint-disable-next-line no-console
        console.warn(message)
      }
    })
  })

  afterEach(() => {
    jest.restoreAllMocks()
  })

  it('renders', () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    render(customRepositorySection({}), {routePayload, wrapper})

    // Assert that the table headers are rendered
    expect(screen.getByText('Apply configurations')).toBeInTheDocument()
    expect(
      screen.getByText('Select repositories to apply configurations and view license consumption information.'),
    ).toBeInTheDocument()
  })

  it('renders a summary of GitHub Advanced Security license availability and usage from an enterprise', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    render(customRepositorySection({}), {routePayload, wrapper})

    const element = screen.queryByTestId('license-summary')
    expect(element).toHaveTextContent(/0 GitHub Advanced Security licenses available, 1 in use by GitHub, Inc/)
  })

  it('does not render a license summary if org does not have GHAS purchased', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    routePayload.capabilities.advancedSecurity.purchased = false
    render(customRepositorySection({}), {routePayload, wrapper})

    const element = screen.queryByTestId('license-summary')
    expect(element).not.toBeInTheDocument()
  })

  it('does not fetch license data when unbundled', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    routePayload.capabilities.advancedSecurity.bundled = false
    routePayload.capabilities.advancedSecurity.codeSecurityPurchased = true
    const {user} = render(customRepositorySection({}), {routePayload, wrapper})

    const firstCheckbox = within(screen.getByTestId('list-view-items')).getAllByRole('checkbox')[0]!
    await user.click(firstCheckbox)

    expectMockFetchCalledTimes(
      '/organizations/github/settings/security_products/repositories/advanced_security_license_summary',
      0,
    )
  })

  it('renders the tally of advanced security license summary data when a repo is selected', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    const {user} = render(customRepositorySection({}), {routePayload, wrapper})

    mockFetch.mockRouteOnce(
      '/organizations/github/settings/security_products/repositories/advanced_security_license_summary',
      {
        licenses_needed: 5,
        licenses_freed: 0,
        failedToFetchLicenses: false,
      },
    )

    const items = screen.getByTestId('list-view-items')
    const checkboxes = within(items).getAllByRole('checkbox')
    const firstCheckbox = checkboxes[0]
    await user.click(firstCheckbox!)
    expect(firstCheckbox).toBeChecked()
    expectMockFetchCalledWith(
      '/organizations/github/settings/security_products/repositories/advanced_security_license_summary',
      {
        repository_ids: ['1'],
      },
    )

    const element = screen.queryByTestId('license-summary')
    await waitFor(
      () => {
        expect(element).toHaveTextContent(
          '0 GitHub Advanced Security licenses available, 1 in use by GitHub, Inc.For configurations with GitHub Advanced Security: 5 licenses required if applying and 0 licenses freed up if disabling',
        )
      },
      {timeout: 2000},
    )
  })

  it('renders the tally of advanced security license summary data when all repos are selected', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    const {user} = render(customRepositorySection({}), {routePayload, wrapper})

    mockFetch.mockRouteOnce(
      '/organizations/github/settings/security_products/repositories/advanced_security_license_summary',
      {
        licenses_needed: 10,
        licenses_freed: 1,
        failedToFetchLicenses: false,
      },
    )

    const selectAllCheckbox = screen.getByTestId('select-all-checkbox')
    await user.click(selectAllCheckbox)
    expect(selectAllCheckbox).toBeChecked()
    expectMockFetchCalledWith(
      '/organizations/github/settings/security_products/repositories/advanced_security_license_summary',
      {
        repository_ids: ['1', '2', '3', '4', '5'],
      },
    )

    const element = screen.queryByTestId('license-summary')
    await waitFor(() => {
      expect(element).toHaveTextContent(
        /0 GitHub Advanced Security licenses available, 1 in use by GitHub, Inc.For configurations with GitHub Advanced Security: 10 licenses required if applying and 1 license freed up if disabling/,
      )
    })

    // Updates the tallys to 0s when no repos are selected
    mockFetch.mockRouteOnce(
      '/organizations/github/settings/security_products/repositories/advanced_security_license_summary',
      {
        licenses_needed: 0,
        licenses_freed: 0,
        failedToFetchLicenses: false,
      },
    )
    await user.click(selectAllCheckbox)
    expect(selectAllCheckbox).not.toBeChecked()
    expectMockFetchCalledWith(
      '/organizations/github/settings/security_products/repositories/advanced_security_license_summary',
      {
        repository_ids: [],
      },
    )

    await waitFor(() => {
      expect(element).toHaveTextContent(/0 GitHub Advanced Security licenses available, 1 in use by GitHub, Inc/)
    })
  })

  it('does not send repo ids if more than 25 repos are present and select all is checked', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    const repositories = createRepos(30)
    routePayload.repositories = repositories

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const customWrapper = (props: any) => wrapper({...props, totalRepositoryCount: repositories.length})

    const {user} = render(customRepositorySection({}), {routePayload, wrapper: customWrapper})

    mockFetch.mockRouteOnce(
      '/organizations/github/settings/security_products/repositories/advanced_security_license_summary',
      {
        licenses_needed: 10,
        licenses_freed: 1,
        failedToFetchLicenses: false,
      },
    )

    const selectAllCheckbox = screen.getByTestId('select-all-checkbox')
    await user.click(selectAllCheckbox)
    expect(selectAllCheckbox).toBeChecked()
    expectMockFetchCalledWith(
      '/organizations/github/settings/security_products/repositories/advanced_security_license_summary',
      {
        repository_ids: [],
      },
    )

    const element = screen.queryByTestId('license-summary')
    await waitFor(() => {
      expect(element).toHaveTextContent(
        /0 GitHub Advanced Security licenses available, 1 in use by GitHub, Inc.For configurations with GitHub Advanced Security: 10 licenses required if applying and 1 license freed up if disabling/,
      )
    })
  }, 10000)

  it('hides licenses required text if organization has not purchased GHAS', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    routePayload.capabilities.advancedSecurity.purchased = false
    render(customRepositorySection({}), {routePayload, wrapper})

    expect(screen.getAllByTestId('repos-list')[0]).toBeInTheDocument()
    expect(screen.getByText('public-repository')).toBeInTheDocument()
    expect(screen.getByText('private-repository')).toBeInTheDocument()

    const itemMetadata = screen.getAllByTestId('list-view-item-metadata-item')
    expect(itemMetadata[0]).not.toHaveTextContent('licenses required')
  })

  describe('pagination', () => {
    it('does not render pagination component when pageCount is 1', async () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      routePayload.pageCount = 1
      render(customRepositorySection(), {routePayload, wrapper})

      expect(screen.queryByTestId('pagination')).not.toBeInTheDocument()
    })

    it('renders pagination when pageCount is greater than 1', async () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      render(customRepositorySection({}), {routePayload, wrapper})

      const pages = screen.getByTestId('pagination')
      expect(pages).toBeInTheDocument()
      expect(within(pages).getByLabelText('Page 1')).toHaveAttribute('aria-current', 'page')
    })

    it('sets the browser history state when paginating', async () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      const {user} = render(customRepositorySection({}), {routePayload, wrapper})

      const pages = screen.getByTestId('pagination')
      expect(pages).toBeInTheDocument()
      expect(window.location.search).toEqual('')

      mockFetch.mockRouteOnce('/organizations/github/settings/security_products/repositories?page=2', searchResults())

      await user.click(within(pages).getByLabelText('Page 2', {exact: false}))

      expectMockFetchCalledTimes('/organizations/github/settings/security_products/repositories?page=2', 1)
      expect(within(pages).getByLabelText('Page 2', {exact: false})).toHaveAttribute('aria-current', 'page')
      expect(window.location.search).toEqual('?page=2')
    })

    it('restores the current page from the browser URL', async () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      render(customRepositorySection({}), {routePayload, wrapper, search: 'q=&page=2'})

      const pages = screen.getByTestId('pagination')
      expect(pages).toBeInTheDocument()

      expect(within(pages).getByLabelText('Page 2', {exact: false})).toHaveAttribute('aria-current', 'page')
    })
  })

  it('does not render a failure banner when failureCounts are empty', async () => {
    // By default the failureCounts in the payload are an empty object, so we don't need to modify it:
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    render(customRepositorySection({}), {routePayload, wrapper})
    expect(screen.queryByTestId('failure-banner')).toBeNull()
  })

  it('does not render a failure banner without the feature flag', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    render(customRepositorySection({previewNext: false}), {routePayload, wrapper})
    expect(screen.queryByTestId('failure-banner')).toBeNull()
  })

  it('renders the failure banner when failureCounts are in the payload', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    const failureCounts = {Unknown: 1}
    render(customRepositorySection({failureCounts}), {routePayload, wrapper})

    const failureBanner = screen.getByTestId('failure-banner')
    expect(failureBanner).toBeInTheDocument()
  })
})

describe('repo table filtering', () => {
  beforeEach(() => {
    setupExpectedAsyncErrorHandler()
  })
  afterEach(() => {
    jest.restoreAllMocks()
  })

  it('suggests both configuration filters', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    render(customRepositorySection({}), {routePayload, wrapper})

    const filterResults = screen.getByTestId('filter-results')
    await updateFilterValue('config')
    await waitFor(() => {
      // Accessible name includes the 'filter' type, which is expected behavior for screen reader users.
      // This is different than the visual text on purpose.
      expect(within(filterResults).getByLabelText('Configuration status, Filter')).toBeInTheDocument()
    })

    const results = within(filterResults).getAllByRole('option')

    expect(results.length).toEqual(2)
    expect(results[0]).toHaveTextContent('Configuration')
    expect(results[1]).toHaveTextContent('Configuration status')
  })

  it('suggests options for configuration status', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    render(customRepositorySection({}), {routePayload, wrapper})

    const filterResults = screen.getByTestId('filter-results')
    await updateFilterValue('config-status:')
    await waitFor(() => {
      // Accessible name includes the 'filter' type, which is expected behavior for screen reader users.
      // This is different than the visual text on purpose.
      expect(within(filterResults).getByLabelText('Attached, Configuration status')).toBeInTheDocument()
    })

    const results = within(filterResults).getAllByRole('option')

    expect(results.length).toEqual(5)
    expect(results[0]).toHaveTextContent('Attached')
    expect(results[1]).toHaveTextContent('Removed')
    expect(results[2]).toHaveTextContent('Failed')
    expect(results[3]).toHaveTextContent('Enforced')
    expect(results[4]).toHaveTextContent('Removed by enterprise')
  })

  it('suggests options for configuration name', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    render(customRepositorySection({}), {routePayload, wrapper})

    const filterResults = screen.getByTestId('filter-results')
    await updateFilterValue('configuration:')
    await waitFor(() => {
      // Accessible name includes the 'filter' type, which is expected behavior for screen reader users.
      // This is different than the visual text on purpose.
      expect(within(filterResults).getByLabelText('High Risk, Configuration')).toBeInTheDocument()
    })

    const results = within(filterResults).getAllByRole('option')

    expect(results.length).toEqual(4)
    expect(results[0]).toHaveTextContent('GitHub recommended')
    expect(results[1]).toHaveTextContent('High Risk')
    expect(results[2]).toHaveTextContent('Low Risk')
    expect(results[3]).toHaveTextContent('None')
  })

  it('suggests options for team and filters by the selected option', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    const {user} = render(customRepositorySection({}), {routePayload, wrapper})
    const filterResults = screen.getByTestId('filter-results')
    const filterTextBar = screen.getByRole('combobox')

    mockFetch.mockRoute(
      'http://localhost/organizations/github/settings/security_products/configurations/filter-suggestions/teams?q=&filter_value=',
      {
        teams: [
          {
            name: 'Team A',
            combined_slug: 'team-a',
            avatar_url: 'https://example.com/avatar.jpg',
          },
        ],
      },
    )
    let suggestion: HTMLElement | undefined
    await updateFilterValue('team:')
    await waitFor(() => {
      suggestion = within(filterResults).getAllByRole('option')[1]
      expect(suggestion).toHaveTextContent('Team A')
    })

    const avatarImage: HTMLImageElement = within(suggestion!).getByAltText('"Team A"')
    expect(avatarImage.src).toMatch(/^https:\/\/example\.com\/avatar\.jpg/)

    await user.click(suggestion!)

    await waitFor(() => {
      expect(filterTextBar).toHaveValue('team:"Team A"')
    })
  })

  it('does not suggest filters for Team when no teams are available', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    routePayload.capabilities.hasTeams = false
    render(customRepositorySection({}), {routePayload, wrapper})
    const filterResults = screen.getByTestId('filter-results')

    await updateFilterValue('team')
    await waitFor(() => {
      expect(within(filterResults).queryByRole('option')).not.toBeInTheDocument()
    })
  })

  it('suggests options for custom property filters', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    const {user} = render(customRepositorySection({}), {routePayload, wrapper})
    const filterResults = screen.getByTestId('filter-results')
    const filterTextBar = screen.getByRole('combobox')

    let suggestion: HTMLElement
    await updateFilterValue('props.custom-property:')
    await waitFor(() => {
      // Accessible name includes the 'filter' type, which is expected behavior for screen reader users.
      // This is different than the visual text on purpose.
      suggestion = within(filterResults).getByRole('option', {name: 'production, Property: custom-property'})
      expect(suggestion).toBeInTheDocument()
    })

    await user.click(suggestion!)

    await waitFor(() => {
      expect(filterTextBar).toHaveValue('props.custom-property:production')
    })
  })

  it('suggests options for failure reason', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    const {user} = render(customRepositorySection({}), {routePayload, wrapper})
    const filterResults = screen.getByTestId('filter-results')
    const filterTextBar = screen.getByRole('combobox')

    let suggestion: HTMLElement
    await updateFilterValue('failure-reason:')
    await waitFor(() => {
      // Accessible name includes the 'filter' type, which is expected behavior for screen reader users.
      // This is different than the visual text on purpose.
      suggestion = within(filterResults).getByRole('option', {name: 'Not enough licenses, Failure reason'})
      expect(suggestion).toBeInTheDocument()
    })

    const results = within(filterResults).getAllByRole('option')
    expect(results.length).toEqual(9)
    expect(results[0]).toHaveTextContent('Actions disabled')
    expect(results[1]).toHaveTextContent('Code scanning')
    expect(results[2]).toHaveTextContent('Enterprise policy')
    expect(results[3]).toHaveTextContent('License data unavailable')
    expect(results[4]).toHaveTextContent('Not enough licenses')
    expect(results[5]).toHaveTextContent('Not purchased')
    expect(results[6]).toHaveTextContent('Runners unavailable')
    expect(results[7]).toHaveTextContent('Runners unavailable')
    expect(results[8]).toHaveTextContent('Unknown')

    await user.click(suggestion!)

    await waitFor(() => {
      expect(filterTextBar).toHaveValue('failure-reason:not_enough_licenses')
    })
  })

  it('suggests the archived filter', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    render(customRepositorySection({}), {routePayload, wrapper})

    const filterResults = screen.getByTestId('filter-results')
    await updateFilterValue('archive')
    await waitFor(() => {
      // Accessible name includes the 'filter' type, which is expected behavior for screen reader users.
      // This is different than the visual text on purpose.
      expect(within(filterResults).getByLabelText('Archived, Filter')).toBeInTheDocument()
    })

    const results = within(filterResults).getAllByRole('option')
    expect(results.length).toEqual(1)
    expect(results[0]).toHaveTextContent('Archived')
  })

  it('restores filters from the browser URL', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    render(customRepositorySection({}), {routePayload, wrapper, search: 'q=visibility:public'})

    expect(screen.getByRole('combobox')).toHaveValue('visibility:public')

    const pages = screen.getByTestId('pagination')
    expect(pages).toBeInTheDocument()
    expect(within(pages).getByLabelText('Page 1', {exact: false})).toHaveAttribute('aria-current', 'page')
  })

  it('restores filters and the current page from the browser URL', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    render(customRepositorySection({}), {routePayload, wrapper, search: 'q=visibility:public&page=2'})

    expect(screen.getByRole('combobox')).toHaveValue('visibility:public')

    const pages = screen.getByTestId('pagination')
    expect(pages).toBeInTheDocument()
    expect(within(pages).getByLabelText('Page 2', {exact: false})).toHaveAttribute('aria-current', 'page')
  })

  describe('filter execution', () => {
    it('can complete a search experience journey', async () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      const {user} = render(customRepositorySection({}), {routePayload, wrapper})

      // First we are going to search for public repos
      mockFetch.mockRouteOnce(
        '/organizations/github/settings/security_products/repositories?q=visibility%3Apublic',
        searchResults(),
      )

      await updateFilterValue('visibility:public')
      await user.click(screen.getByLabelText('Search'))

      expectMockFetchCalledTimes(
        '/organizations/github/settings/security_products/repositories?q=visibility%3Apublic',
        1,
      )

      const pages = screen.getByTestId('pagination')
      expect(pages).toBeInTheDocument()
      expect(within(pages).getByLabelText('Page 1', {exact: false})).toHaveAttribute('aria-current', 'page')
      expect(window.location.search).toEqual('?q=visibility%3Apublic')

      // Now we are going to the second page of results
      mockFetch.mockRouteOnce(
        '/organizations/github/settings/security_products/repositories?q=visibility%3Apublic&page=2',
        searchResults(),
      )

      await user.click(within(pages).getByLabelText('Page 2', {exact: false}))

      expectMockFetchCalledTimes(
        '/organizations/github/settings/security_products/repositories?q=visibility%3Apublic&page=2',
        1,
      )

      expect(within(pages).getByLabelText('Page 2', {exact: false})).toHaveAttribute('aria-current', 'page')
      expect(window.location.search).toEqual('?q=visibility%3Apublic&page=2')

      // Now we are going to clear the search
      mockFetch.mockRouteOnce('/organizations/github/settings/security_products/repositories?', searchResults())
      await user.click(screen.getByLabelText('Clear filter'))
      expect(screen.getByRole('combobox')).toHaveValue('')

      expectMockFetchCalledTimes('/organizations/github/settings/security_products/repositories?', 1)

      expect(within(pages).getByLabelText('Page 1', {exact: false})).toHaveAttribute('aria-current', 'page')
      expect(window.location.search).toEqual('')
    })
  })

  describe('security feature filtering', () => {
    it('suggests filter options for GHAS', async () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      render(customRepositorySection({}), {routePayload, wrapper})

      const filterResults = screen.getByTestId('filter-results')
      await updateFilterValue('advanced-security:')
      await waitFor(() => {
        // Accessible name includes the 'filter' type, which is expected behavior for screen reader users.
        // This is different than the visual text on purpose.
        expect(within(filterResults).getByLabelText('Enabled, GitHub Advanced Security')).toBeInTheDocument()
      })

      const results = within(filterResults).getAllByRole('option')

      expect(results.length).toEqual(2)
      expect(results[0]).toHaveTextContent('Enabled')
      expect(results[1]).toHaveTextContent('Disabled')
    })

    it('does not include the GHAS filter on an unbundled org', async () => {
      const routePayload = getUnbundledOrganizationSettingsSecurityProductsRoutePayload()
      render(customRepositorySection({}), {routePayload, wrapper})

      const filterResults = screen.getByTestId('filter-results')
      await updateFilterValue('advanced-security:')
      await waitFor(() => {
        expect(within(filterResults).queryByRole('option')).not.toBeInTheDocument()
      })
    })

    it('suggests filter options for Dependabot alerts', async () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      render(customRepositorySection({}), {routePayload, wrapper})

      const filterResults = screen.getByTestId('filter-results')
      await updateFilterValue('dependabot-alerts:')
      await waitFor(() => {
        // Accessible name includes the 'filter' type, which is expected behavior for screen reader users.
        // This is different than the visual text on purpose.
        expect(within(filterResults).getByLabelText('Enabled, Dependabot alerts')).toBeInTheDocument()
      })

      const results = within(filterResults).getAllByRole('option')

      expect(results.length).toEqual(2)
      expect(results[0]).toHaveTextContent('Enabled')
      expect(results[1]).toHaveTextContent('Disabled')
    })

    it('does not suggest filter options for Dependabot alerts if product is not available', async () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      routePayload.securityProducts.dependabot_alerts.availability = SecurityProductAvailability.Unavailable
      render(customRepositorySection({}), {routePayload, wrapper})

      const filterResults = screen.getByTestId('filter-results')
      await updateFilterValue('dependabot-alerts:')
      await waitFor(() => {
        expect(within(filterResults).queryByRole('option')).not.toBeInTheDocument()
      })
    })

    it('suggests filter options for Dependabot security updates', async () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      render(customRepositorySection({}), {routePayload, wrapper})

      const filterResults = screen.getByTestId('filter-results')
      await updateFilterValue('dependabot-security-updates:')
      await waitFor(() => {
        // Accessible name includes the 'filter' type, which is expected behavior for screen reader users.
        // This is different than the visual text on purpose.
        expect(within(filterResults).getByLabelText('Enabled, Dependabot security updates')).toBeInTheDocument()
      })

      const results = within(filterResults).getAllByRole('option')

      expect(results.length).toEqual(2)
      expect(results[0]).toHaveTextContent('Enabled')
      expect(results[1]).toHaveTextContent('Disabled')
    })

    it('does not suggest filter options for Dependabot security updates if product is not available', async () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      routePayload.securityProducts.dependabot_updates.availability = SecurityProductAvailability.Unavailable
      render(customRepositorySection({}), {routePayload, wrapper})

      const filterResults = screen.getByTestId('filter-results')
      await updateFilterValue('dependabot-security-updates:')
      await waitFor(() => {
        expect(within(filterResults).queryByRole('option')).not.toBeInTheDocument()
      })
    })

    it('suggests filter options for Code scanning alerts', async () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      render(customRepositorySection({}), {routePayload, wrapper})

      const filterResults = screen.getByTestId('filter-results')
      await updateFilterValue('code-scanning-alerts:')
      await waitFor(() => {
        // Accessible name includes the 'filter' type, which is expected behavior for screen reader users.
        // This is different than the visual text on purpose.
        expect(within(filterResults).getByLabelText('Enabled, Code scanning alerts')).toBeInTheDocument()
      })

      const results = within(filterResults).getAllByRole('option')

      expect(results.length).toEqual(2)
      expect(results[0]).toHaveTextContent('Enabled')
      expect(results[1]).toHaveTextContent('Disabled')
    })

    it('does not suggest filter options for Code scanning alerts if product is not available', async () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      routePayload.securityProducts.code_scanning.availability = SecurityProductAvailability.Unavailable
      render(customRepositorySection({}), {routePayload, wrapper})

      const filterResults = screen.getByTestId('filter-results')
      await updateFilterValue('code-scanning-alerts:')
      await waitFor(() => {
        expect(within(filterResults).queryByRole('option')).not.toBeInTheDocument()
      })
    })

    it('suggests filter options for Code scanning default setup', async () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      render(customRepositorySection({}), {routePayload, wrapper})

      const filterResults = screen.getByTestId('filter-results')
      await updateFilterValue('code-scanning-default-setup:')
      await waitFor(() => {
        // Accessible name includes the 'filter' type, which is expected behavior for screen reader users.
        // This is different than the visual text on purpose.
        expect(within(filterResults).getByLabelText('Enabled, Code scanning default setup')).toBeInTheDocument()
      })

      const results = within(filterResults).getAllByRole('option')

      expect(results.length).toEqual(3)
      expect(results[0]).toHaveTextContent('Enabled')
      expect(results[1]).toHaveTextContent('Eligible')
      expect(results[2]).toHaveTextContent('Not eligible')
    })

    it('does not suggest filter options for Code scanning default setup if product is not available', async () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      routePayload.securityProducts.code_scanning.availability = SecurityProductAvailability.Unavailable
      render(customRepositorySection({}), {routePayload, wrapper})

      const filterResults = screen.getByTestId('filter-results')
      await updateFilterValue('code-scanning-default-setup:')
      await waitFor(() => {
        expect(within(filterResults).queryByRole('option')).not.toBeInTheDocument()
      })
    })

    it('suggests filter options for Secret scanning alerts', async () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      render(customRepositorySection({}), {routePayload, wrapper})

      const filterResults = screen.getByTestId('filter-results')
      await updateFilterValue('secret-scanning-alerts:')
      await waitFor(() => {
        // Accessible name includes the 'filter' type, which is expected behavior for screen reader users.
        // This is different than the visual text on purpose.
        expect(within(filterResults).getByLabelText('Enabled, Secret scanning alerts')).toBeInTheDocument()
      })

      const results = within(filterResults).getAllByRole('option')

      expect(results.length).toEqual(2)
      expect(results[0]).toHaveTextContent('Enabled')
      expect(results[1]).toHaveTextContent('Disabled')
    })

    it('does not suggest filter options for Secret scanning alerts if product is not available', async () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      routePayload.securityProducts.secret_scanning.availability = SecurityProductAvailability.Unavailable
      render(customRepositorySection({}), {routePayload, wrapper})

      const filterResults = screen.getByTestId('filter-results')
      await updateFilterValue('secret-scanning-alerts:')
      await waitFor(() => {
        expect(within(filterResults).queryByRole('option')).not.toBeInTheDocument()
      })
    })

    it('suggests filter options for Push protection', async () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      render(customRepositorySection({}), {routePayload, wrapper})

      const filterResults = screen.getByTestId('filter-results')
      await updateFilterValue('secret-scanning-push-protection:')
      await waitFor(() => {
        // Accessible name includes the 'filter' type, which is expected behavior for screen reader users.
        // This is different than the visual text on purpose.
        expect(within(filterResults).getByLabelText('Enabled, Push protection')).toBeInTheDocument()
      })

      const results = within(filterResults).getAllByRole('option')

      expect(results.length).toEqual(2)
      expect(results[0]).toHaveTextContent('Enabled')
      expect(results[1]).toHaveTextContent('Disabled')
    })

    it('does not suggest filter options for Push protection if product is not available', async () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      routePayload.securityProducts.secret_scanning.availability = SecurityProductAvailability.Unavailable
      render(customRepositorySection({}), {routePayload, wrapper})

      const filterResults = screen.getByTestId('filter-results')
      await updateFilterValue('secret-scanning-push-protection:')
      await waitFor(() => {
        expect(within(filterResults).queryByRole('option')).not.toBeInTheDocument()
      })
    })

    it('does not suggest filter options for GHAS if ghasPurchased and enterpriseOwned are false', async () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      routePayload.capabilities.advancedSecurity.purchased = false
      routePayload.capabilities.enterpriseOwned = false
      render(customRepositorySection({}), {routePayload, wrapper})

      const filterResults = screen.getByTestId('filter-results')
      await updateFilterValue('advanced-security:')
      await waitFor(() => {
        expect(within(filterResults).queryByRole('option')).not.toBeInTheDocument()
      })
    })

    it('suggests filter options for Dependabot alerts if ghasPurchased and enterPriseOwned are flase', async () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      routePayload.capabilities.advancedSecurity.purchased = false
      routePayload.capabilities.enterpriseOwned = false
      render(customRepositorySection({}), {routePayload, wrapper})

      const filterResults = screen.getByTestId('filter-results')
      await updateFilterValue('dependabot-alerts:')
      await waitFor(() => {
        // Accessible name includes the 'filter' type, which is expected behavior for screen reader users.
        // This is different than the visual text on purpose.
        expect(within(filterResults).getByLabelText('Enabled, Dependabot alerts')).toBeInTheDocument()
      })

      const results = within(filterResults).getAllByRole('option')

      expect(results.length).toEqual(2)
      expect(results[0]).toHaveTextContent('Enabled')
      expect(results[1]).toHaveTextContent('Disabled')
    })
  })
})

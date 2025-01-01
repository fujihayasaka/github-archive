import {render} from '@github-ui/react-core/test-utils'
import {screen, act} from '@testing-library/react'
import OrgFailuresBanner from '../../components/EnterpriseSettings/OrgFailuresBanner'
import type {EnterpriseOrgFailures} from '../../security-products-enablement-types'
import {swallowCSSParsingError} from '../../test-utils/test-helper'

describe('OrgFailuresBanner', () => {
  beforeEach(swallowCSSParsingError)

  it('does not render if there are no failures (empty object)', async () => {
    const failures = {} as EnterpriseOrgFailures
    render(<OrgFailuresBanner failures={failures} />)

    // Use queryByTestId so we don't fail when the element isn't found:
    const element = screen.queryByTestId('org-failures-banner')
    expect(element).not.toBeInTheDocument()
  })

  it('does not render if there are no failures (payload w/o failures)', async () => {
    render(
      <OrgFailuresBanner
        failures={{
          totalRepoFailures: 0,
          orgs: [],
        }}
      />,
    )

    // Use queryByTestId so we don't fail when the element isn't found:
    const element = screen.queryByTestId('org-failures-banner')
    expect(element).not.toBeInTheDocument()
  })

  it('shows one org name', async () => {
    render(
      <OrgFailuresBanner
        failures={{
          totalRepoFailures: 1,
          orgs: [{name: 'github', repoFailures: 1}],
        }}
      />,
    )
    const element = screen.getByTestId('org-failures-banner')
    expect(element).toHaveTextContent(
      'Applying security configurations failed for 1 repository in the following organization: github',
    )
  })

  it('shows two org names', async () => {
    render(
      <OrgFailuresBanner
        failures={{
          totalRepoFailures: 2,
          orgs: [
            {name: 'github', repoFailures: 1},
            {name: 'primer', repoFailures: 1},
          ],
        }}
      />,
    )
    const element = screen.getByTestId('org-failures-banner')
    expect(element).toHaveTextContent(
      'Applying security configurations failed for 2 repositories in the following organizations: github and primer',
    )
  })

  it('shows three org names', async () => {
    render(
      <OrgFailuresBanner
        failures={{
          totalRepoFailures: 3,
          orgs: [
            {name: 'github', repoFailures: 1},
            {name: 'primer', repoFailures: 1},
            {name: 'atom', repoFailures: 1},
          ],
        }}
      />,
    )
    const element = screen.getByTestId('org-failures-banner')
    expect(element).toHaveTextContent(
      'Applying security configurations failed for 3 repositories in the following organizations: github, primer and atom',
    )
  })

  it('shows a truncated message if there are more than three org failures with a link', async () => {
    render(
      <OrgFailuresBanner
        failures={{
          totalRepoFailures: 40,
          orgs: [
            {name: 'github', repoFailures: 10},
            {name: 'primer', repoFailures: 10},
            {name: 'atom', repoFailures: 10},
            {name: 'copilot', repoFailures: 10},
          ],
        }}
      />,
    )
    const element = screen.getByTestId('org-failures-banner')
    expect(element).toHaveTextContent('40 repositories across 4 organizations failed to apply.')
    expect(element).toHaveTextContent('View list of failed organizations.')
  })

  it('shows a dialog when the link is clicked', async () => {
    render(
      <OrgFailuresBanner
        failures={{
          totalRepoFailures: 40,
          orgs: [
            {name: 'github', repoFailures: 10},
            {name: 'primer', repoFailures: 10},
            {name: 'atom', repoFailures: 10},
            {name: 'copilot', repoFailures: 10},
          ],
        }}
      />,
    )
    const element = screen.getByTestId('org-failures-banner')
    expect(element).toHaveTextContent('40 repositories across 4 organizations failed to apply.')
    expect(element).toHaveTextContent('View list of failed organizations.')

    await act(() => {
      screen.getByText('View list of failed organizations.').click()
    })
    expect(screen.getByTestId('failed-orgs-dialog-list')).toBeInTheDocument()
    expect(screen.getAllByRole('listitem')).toHaveLength(4)
  })
})

import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {OrgFailuresDialog} from '../../components/EnterpriseSettings/OrgFailuresDialog'
import type {EnterpriseOrgFailures} from '../../security-products-enablement-types'
import {swallowCSSParsingError} from '../../test-utils/test-helper'

describe('OrgFailuresDialog', () => {
  beforeEach(swallowCSSParsingError)

  it('does not render if there are no failures (empty object)', async () => {
    const failures = {} as EnterpriseOrgFailures
    render(
      <OrgFailuresDialog
        failures={failures}
        setShowFailedOrgDialog={function (): void {
          throw new Error('Function not implemented.')
        }}
      />,
    )

    // Use queryByTestId so we don't fail when the element isn't found:
    const element = screen.queryByTestId('failed-orgs-dialog')
    expect(element).not.toBeInTheDocument()
  })

  it('renders a list of org names with number of failed repos', async () => {
    render(
      <OrgFailuresDialog
        failures={{
          totalRepoFailures: 8,
          orgs: [{name: 'github', repoFailures: 2}],
        }}
        setShowFailedOrgDialog={function (): void {
          throw new Error('Function not implemented.')
        }}
      />,
    )
    const element = screen.getByTestId('failed-orgs-dialog-list')
    expect(element).toHaveTextContent('github (2 failed repositories)')
  })
})

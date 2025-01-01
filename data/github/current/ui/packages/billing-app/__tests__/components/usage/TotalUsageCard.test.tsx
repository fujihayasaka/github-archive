import {render} from '@github-ui/react-core/test-utils'
import {act, screen} from '@testing-library/react'

import {TotalUsageCard} from '../../../components/usage'
import {PageContext} from '../../../App'

describe('TotalUsageCard', () => {
  test('Shows the correct copy for enterprise owner / billing manager', async () => {
    render(
      <PageContext.Provider
        value={{isEnterpriseRoute: true, isOrganizationRoute: false, isUserRoute: false, isStafftoolsRoute: false}}
      >
        <TotalUsageCard customerSelections={[]} />
      </PageContext.Provider>,
    )

    await act(async () => {
      expect(screen.getByTestId('usage-disclaimer')).toHaveTextContent(
        'Showing gross metered usage for your enterprise including all cost centers',
      )
    })
  })

  test('Shows the correct copy for organization admins viewing enterprise usage', async () => {
    render(
      <PageContext.Provider
        value={{isEnterpriseRoute: true, isOrganizationRoute: false, isUserRoute: false, isStafftoolsRoute: false}}
      >
        <TotalUsageCard customerSelections={[]} isOrgAdmin />
      </PageContext.Provider>,
    )

    await act(async () => {
      expect(screen.getByTestId('usage-disclaimer')).toHaveTextContent(
        'Showing gross metered usage for all organizations which you own',
      )
    })
  })

  test('Shows the correct copy for organizations', async () => {
    render(
      <PageContext.Provider
        value={{isEnterpriseRoute: false, isOrganizationRoute: true, isUserRoute: false, isStafftoolsRoute: false}}
      >
        <TotalUsageCard customerSelections={[]} />
      </PageContext.Provider>,
    )

    await act(async () => {
      expect(screen.getByTestId('usage-disclaimer')).toHaveTextContent(
        'Showing gross metered usage for your organization',
      )
    })
  })
})

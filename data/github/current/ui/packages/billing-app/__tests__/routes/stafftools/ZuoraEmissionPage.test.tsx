import {render} from '@github-ui/react-core/test-utils'
import {screen, waitFor} from '@testing-library/react'

import type {ZuoraEmissionPayload} from '../../../routes/stafftools'
import {ZuoraEmissionPage} from '../../../routes/stafftools'
import {getZuoraEmissionsRequest} from '../../../services/zuora_emissions'
import type {ZuoraEmission} from '../../../types/zuora-emissions'

import {mockZuoraEmission} from '../../../test-utils/mock-data'

function zuoraEmissionRoutePayload({
  slug = 'test',
  zuoraEmissions = [mockZuoraEmission],
}: {
  slug?: string
  zuoraEmissions: ZuoraEmission[]
  is_stafftools_route: true
}): ZuoraEmissionPayload {
  return {
    is_stafftools_route: true,
    slug,
    zuoraEmissions,
  }
}
jest.mock('../../../services/zuora_emissions', () => ({
  getZuoraEmissionsRequest: jest.fn(),
}))

describe('zuora Emissions exist', () => {
  describe('When emissions exist', () => {
    it('displays the emissions for this customer', async () => {
      ;(getZuoraEmissionsRequest as jest.Mock).mockResolvedValue({
        statusCode: 200,
        payload: {
          zuoraEmissions: [mockZuoraEmission],
          slug: 'test',
          is_stafftools_route: true,
        },
      })
      const routePayload = zuoraEmissionRoutePayload({
        zuoraEmissions: [mockZuoraEmission],
        slug: 'test',
        is_stafftools_route: true,
      })
      const {user} = render(<ZuoraEmissionPage />, {routePayload})

      expect(screen.getByTestId('zuora-emissions-heading')).toHaveTextContent('Zuora Emissions')
      const DatePickerButtonDay = screen.getByTestId('anchor-button')
      await user.click(DatePickerButtonDay)
      const dayButton = screen.getByText('21')
      await user.click(dayButton)

      await waitFor(() => expect(screen.getByRole('table')).toHaveTextContent('Gross'))
    })

    describe('When emissions dont exist', () => {
      it('displays the blankslate', async () => {
        ;(getZuoraEmissionsRequest as jest.Mock).mockResolvedValue({
          statusCode: 200,
          payload: {
            zuoraEmissions: [],
            slug: 'test',
            is_stafftools_route: true,
          },
        })
        const routePayload = zuoraEmissionRoutePayload({
          zuoraEmissions: [],
          slug: 'test',
          is_stafftools_route: true,
        })
        const {user} = render(<ZuoraEmissionPage />, {routePayload})

        expect(screen.getByTestId('zuora-emissions-heading')).toHaveTextContent('Zuora Emissions')
        const DatePickerButtonDay = screen.getByTestId('anchor-button')
        await user.click(DatePickerButtonDay)
        const dayButton = screen.getByText('21')
        await user.click(dayButton)

        await waitFor(() =>
          expect(screen.getByTestId('blankslate-container')).toHaveTextContent(
            'Customer has no Zuora Emissions for this date.',
          ),
        )
      })
    })
  })
})

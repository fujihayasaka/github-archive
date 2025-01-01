import {render} from '@github-ui/react-core/test-utils'
import {screen, waitFor} from '@testing-library/react'

import type {AzureEmissionPayload} from '../../../routes/stafftools'
import {AzureEmissionPage} from '../../../routes/stafftools'
import {getAzureEmissionsRequest} from '../../../services/azure_emissions'
import type {AzureEmission} from '../../../types/azure-emissions'

import {mockAzureEmission} from '../../../test-utils/mock-data'

function azureEmissionRoutePayload({
  slug = 'test',
  azureEmissions = [mockAzureEmission],
}: {
  slug?: string
  azureEmissions: AzureEmission[]
  is_stafftools_route: true
}): AzureEmissionPayload {
  return {
    is_stafftools_route: true,
    slug,
    azureEmissions,
    products: [
      {
        friendlyName: 'Test Product',
        productName: 'test-product',
      },
    ],
  }
}
jest.mock('../../../services/azure_emissions', () => ({
  getAzureEmissionsRequest: jest.fn(),
}))

describe('Azure Emissions exist', () => {
  describe('When emissions exist', () => {
    it('displays the emissions for this customer', async () => {
      ;(getAzureEmissionsRequest as jest.Mock).mockResolvedValue({
        statusCode: 200,
        payload: {
          azureEmissions: [mockAzureEmission],
          products: [
            {
              friendlyName: 'Test Product',
              productName: 'test-product',
            },
          ],
          slug: 'test',
          is_stafftools_route: true,
        },
      })
      const routePayload = azureEmissionRoutePayload({
        azureEmissions: [mockAzureEmission],
        slug: 'test',
        is_stafftools_route: true,
      })
      const {user} = render(<AzureEmissionPage />, {routePayload})

      expect(screen.getByTestId('azure-emissions-heading')).toHaveTextContent('Azure Emissions')
      expect(screen.getByTestId('product-list')).toHaveTextContent('Test Product')
      const DatePickerButtonDay = screen.getByTestId('anchor-button')
      await user.click(DatePickerButtonDay)
      const dayButton = screen.getByText('21')
      await user.click(dayButton)

      await waitFor(() => expect(screen.getByRole('table')).toHaveTextContent(mockAzureEmission.usageEntity.name))
      await waitFor(() => expect(screen.getByRole('table')).toHaveTextContent(mockAzureEmission.friendlySkuName))
    })

    describe('When emissions dont exist', () => {
      it('displays the blankslate', async () => {
        ;(getAzureEmissionsRequest as jest.Mock).mockResolvedValue({
          statusCode: 200,
          payload: {
            azureEmissions: [],
            products: [
              {
                friendlyName: 'Test Product',
                productName: 'test-product',
              },
            ],
            slug: 'test',
            is_stafftools_route: true,
          },
        })
        const routePayload = azureEmissionRoutePayload({
          azureEmissions: [],
          slug: 'test',
          is_stafftools_route: true,
        })
        const {user} = render(<AzureEmissionPage />, {routePayload})

        expect(screen.getByTestId('azure-emissions-heading')).toHaveTextContent('Azure Emissions')
        expect(screen.getByTestId('product-list')).toHaveTextContent('Test Product')
        const DatePickerButtonDay = screen.getByTestId('anchor-button')
        await user.click(DatePickerButtonDay)
        const dayButton = screen.getByText('21')
        await user.click(dayButton)

        await waitFor(() =>
          expect(screen.getByTestId('blankslate-container')).toHaveTextContent(
            'Customer has no Azure Emissions for this date.',
          ),
        )
      })
    })
  })
})

import {useState} from 'react'
import {SmileyIcon} from '@primer/octicons-react'
import {Box, Heading, Spinner, ActionMenu, ActionList} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'
import Layout from '../../components/Layout'

import {DatePicker} from '@github-ui/date-picker'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'

import AzureEmissionTable from '../../components/azure_emissions/AzureEmissionTable'
import {RequestState} from '../../enums'
import type {AzureEmission, EmissionDate, Product, ProductOption} from '../../types/azure-emissions'
import useAzureEmissions from '../../hooks/azure_emissions/use-azure-emissions'

export interface AzureEmissionPayload {
  is_stafftools_route: boolean
  slug: string
  azureEmissions: AzureEmission[]
  products: Product[]
}

export function AzureEmissionPage() {
  const payload = useRoutePayload<AzureEmissionPayload>()
  const today = new Date()
  const yesterday = new Date(today)
  yesterday.setDate(today.getDate() - 1)
  const [currentDate, setCurrentDate] = useState<EmissionDate>({
    year: yesterday.getFullYear(),
    month: yesterday.getMonth() + 1,
    day: yesterday.getDate(),
  })
  const [product, setSelectedProduct] = useState<Product>({
    friendlyName: payload?.products[0]?.friendlyName || '',
    productName: payload?.products[0]?.productName || '',
  })
  const {azureEmissions, requestState} = useAzureEmissions({
    enterpriseSlug: payload.slug,
    emissionDate: currentDate,
    selectedProduct: product.productName,
  })
  const [productOptions, _] = useState<ProductOption[]>(
    payload.products.map(productItem => ({
      friendlyName: productItem.friendlyName,
      productName: productItem.productName,
      selected: false,
    })),
  )

  const toggle = (name: string) => {
    productOptions.map(option => {
      option.selected = false
    })
    productOptions.map(option => {
      if (option.productName === name) {
        option.selected = !option.selected
        setSelectedProduct(option)
      }
      return option
    })
  }

  return (
    <Layout>
      <header className="Subhead">
        <Heading
          data-testid="azure-emissions-heading"
          as="h2"
          sx={{font: 'var(--text-subtitle-shorthand)', fontSize: '4'}}
          className="Subhead-heading"
        >
          Azure Emissions
        </Heading>
      </header>
      <div>
        Choose a usage date to see the emissions for that date. This tool captures the Azure emission records in
        billing-platform and the record in Azure Storage Table.
      </div>
      <br />
      <br />
      <Box sx={{display: 'flex'}}>
        <Box sx={{flex: 1, marginRight: -200}}>
          <DatePicker
            variant="single"
            dateFormat="long"
            onChange={selection => {
              if (selection) {
                selection = new Date(selection)
                const emissionDate: EmissionDate = {
                  year: selection.getFullYear(),
                  month: selection.getMonth() + 1,
                  day: selection.getDate(),
                }
                setCurrentDate(emissionDate)
              }
            }}
            value={new Date(currentDate.year, currentDate.month - 1, currentDate.day)}
            placeholder="Choose a Usage Date"
            maxDate={yesterday}
          />
        </Box>
        <Box data-testid={'product-list'} sx={{flex: 2}}>
          <ActionMenu>
            <ActionMenu.Button>{product.friendlyName || 'Choose a product'}</ActionMenu.Button>
            <ActionMenu.Overlay width="medium">
              <ActionList>
                <ActionList.Group selectionVariant="multiple">
                  {productOptions.map(options => (
                    <ActionList.Item
                      key={options.productName}
                      selected={options.selected}
                      onSelect={() => toggle(options.productName)}
                    >
                      {options.friendlyName}
                    </ActionList.Item>
                  ))}
                  <ActionList.Divider />
                </ActionList.Group>
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        </Box>
      </Box>
      <br />
      <br />
      {azureEmissions.length > 0 && <AzureEmissionTable azureEmissions={azureEmissions} />}
      {requestState === RequestState.LOADING && <Spinner />}
      {azureEmissions.length === 0 && requestState === RequestState.IDLE && (
        <div data-testid={'blankslate-container'}>
          <Blankslate>
            <Blankslate.Visual>
              <SmileyIcon size={36} />
            </Blankslate.Visual>
            <Blankslate.Heading>Customer has no Azure Emissions for this date.</Blankslate.Heading>
            <Blankslate.Description>
              Please try selecting another date and/or product to find emissions
            </Blankslate.Description>
          </Blankslate>
        </div>
      )}
    </Layout>
  )
}

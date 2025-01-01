import {useState} from 'react'
import {Box, UnderlineNav} from '@primer/react'

import {DefaultUsageContainer} from './DefaultUsageContainer'
import {SeatBasedUsageContainer} from './SeatBasedUsageContainer'

import {PRODUCT_TAB_ICON_MAP, PRODUCT_TAB_TEXT_MAP, Products, MeteredProducts, SeatBasedProducts} from '../../constants'

import type {Customer} from '../../types/common'
import type {EnabledProduct} from '../../types/products'
import type {Filters} from '../../types/usage'
import {ModelsUsageContainer} from './ModelsUsageContainer'

interface Props {
  customer: Customer
  enabledProducts: EnabledProduct[]
  filters: Filters
  isCopilotStandalone: boolean
  isOnlyOrgAdmin: boolean
  codingAgentEnabled: boolean
  sparkEnabled: boolean
}

export function ProductUsageContainer({
  enabledProducts,
  filters,
  isCopilotStandalone,
  isOnlyOrgAdmin,
  codingAgentEnabled,
  sparkEnabled,
}: Props) {
  const sortedEnabledProducts = [...enabledProducts].sort((a, b) => a.name.localeCompare(b.name))
  const [selectedProduct, setSelectedProduct] = useState<Products>(sortedEnabledProducts[0]?.name || Products.actions)

  // Find the selected product data outside of the return statement
  const selectedProductData = sortedEnabledProducts.find((product: EnabledProduct) => product.name === selectedProduct)

  // Render the selected product usage container
  const renderSelectedProductContainer = () => {
    if (!selectedProductData) {
      return null
    }

    return (
      <div
        id={`product-panel-${selectedProductData.name}`}
        role="tabpanel"
        aria-labelledby={`${selectedProductData.name}-tab`}
        key={`${selectedProductData.name}-tab-pane`}
        data-testid={`${selectedProductData.name}-tab-pane`}
        tabIndex={0}
      >
        {selectedProductData.name === 'models' && (
          <ModelsUsageContainer
            filters={{...filters, product: selectedProductData.name}}
            product={selectedProductData}
          />
        )}
        {selectedProductData.name in MeteredProducts && selectedProductData.name !== 'models' && (
          <DefaultUsageContainer
            filters={{...filters, product: selectedProductData.name}}
            isOnlyOrgAdmin={isOnlyOrgAdmin}
            product={selectedProductData}
          />
        )}
        {selectedProductData.name in SeatBasedProducts && (
          <SeatBasedUsageContainer
            filters={{...filters, product: selectedProductData.name}}
            isCopilotStandalone={isCopilotStandalone}
            productName={PRODUCT_TAB_TEXT_MAP[selectedProductData.name]}
            codingAgentEnabled={codingAgentEnabled}
            sparkEnabled={sparkEnabled}
          />
        )}
      </div>
    )
  }

  return (
    <>
      {sortedEnabledProducts.length > 0 && (
        <Box sx={{mb: 4}}>
          <UnderlineNav aria-label="Products selector" sx={{pl: 0, mb: 3}}>
            {sortedEnabledProducts.map((product: EnabledProduct) => (
              <UnderlineNav.Item
                id={`${product.name}-tab`}
                as="button"
                aria-current={selectedProduct === product.name ? 'page' : undefined}
                onSelect={e => {
                  e.preventDefault()
                  setSelectedProduct(product.name)
                }}
                icon={PRODUCT_TAB_ICON_MAP[product.name]}
                sx={{
                  textTransform: 'capitalize',
                  cursor: 'pointer',
                  '&:focus-visible': {
                    outline: '2px solid var(--focus-outlineColor)',
                    outlineOffset: '2px',
                    borderRadius: 'var(--borderRadius-medium)',
                  },
                  '@media (hover: none)': {
                    '&:hover': {
                      textDecoration: 'none',
                    },
                  },
                }}
                key={`${product.name}-tab`}
                data-testid={`${product.name}-tab`}
              >
                {PRODUCT_TAB_TEXT_MAP[product.name]}
              </UnderlineNav.Item>
            ))}
          </UnderlineNav>

          <div>{renderSelectedProductContainer()}</div>
        </Box>
      )}
    </>
  )
}

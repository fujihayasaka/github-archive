import {Box, Heading, Text} from '@primer/react'
import {useEffect, useState} from 'react'

import type {Product} from '../../types/products'
import {Fonts} from '../../utils/style'
import type {PricingDetails} from '../../types/pricings'

interface Props {
  budgetValue: string
  enabledProducts: Product[]
  enabledSkus: PricingDetails[]
}

export function BudgetSelectedProduct({budgetValue, enabledProducts, enabledSkus}: Props) {
  const [budgetValueName, setBudgetValueName] = useState<string>('')
  const [budgetHeaderName, setBudgetHeaderName] = useState<string>('')

  useEffect(() => {
    const product = enabledProducts.find(item => item.name === budgetValue)
    if (product) {
      setBudgetValueName(product.friendlyProductName)
      setBudgetHeaderName('Product')
      return
    }

    const sku = enabledSkus.find(item => item.sku === budgetValue)
    if (sku) {
      setBudgetValueName(sku.friendlyName)
      setBudgetHeaderName('Sku')
    }
  }, [budgetValue, enabledProducts, enabledSkus])

  return (
    <Box sx={{mb: 4}}>
      <Heading as="h2" sx={{fontSize: Fonts.SectionHeadingFontSize, mb: 2}} className="Box-title">
        {budgetHeaderName ?? 'Unknown'}
      </Heading>
      <div className="Box">
        <div className="Box-row">
          <Text sx={{fontWeight: 'bold'}}>{budgetValueName ?? 'Unknown'}</Text>
        </div>
      </div>
    </Box>
  )
}

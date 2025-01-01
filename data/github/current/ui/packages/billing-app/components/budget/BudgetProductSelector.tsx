import {Box, Heading, FormControl, RadioGroup, Radio} from '@primer/react'

import type {Product} from '../../types/products'

import styles from './BudgetProductSelector.module.css'

interface Props {
  products: Product[]
  budgetProduct: string
  setBudgetProduct: React.Dispatch<React.SetStateAction<string>>
}

export function BudgetProductSelector({products, budgetProduct, setBudgetProduct}: Props) {
  return (
    <Box sx={{py: 2}}>
      <Heading as="h3" sx={{fontSize: 2}} className="Box-title">
        Product
      </Heading>
      <RadioGroup
        name="budget-product-choices"
        aria-labelledby="budget-product-choices"
        onChange={selection => selection && setBudgetProduct(selection)}
        className={styles.RadioGroup}
      >
        <RadioGroup.Label className={styles.RadioGroup_Label}>
          Select the product to include in this budget.
        </RadioGroup.Label>
        <div className="Box">
          {products.map(product => (
            <div key={product.name} className="Box-row">
              <FormControl>
                <Radio value={product.name} name="product" checked={budgetProduct === product.name} />
                <FormControl.Label>{product.friendlyProductName}</FormControl.Label>
              </FormControl>
            </div>
          ))}
        </div>
      </RadioGroup>
    </Box>
  )
}

import {FormControl, Heading, Radio, RadioGroup} from '@primer/react'
import type {Product} from '../../types/products'
import styles from './BudgetProductSelector.module.css'
import {useState} from 'react'
import type {ActionListItemInput} from '@primer/react/deprecated'
import type {PricingDetails} from '../../types/pricings'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {SelectPanelWrapper} from './BudgetSelectPanelWrapper'
import type {Products} from '../../constants'
import {PRODUCT_TAB_ICON_MAP, PRODUCT_TAB_TEXT_MAP, CopilotPremiumRequestSku} from '../../constants'
import {MarkGithubIcon} from '@primer/octicons-react'
import {InlineMessage} from '@primer/react/experimental'
import {ModelsBillingErrorMessage} from './ModelsBillingErrorMessage'

interface Props {
  products: Product[]
  skus: PricingDetails[]
  budgetType: string
  budgetValue: string
  setBudgetType: React.Dispatch<React.SetStateAction<string>>
  setBudgetValue: React.Dispatch<React.SetStateAction<string>>
  isUserRoute: boolean
  showSkuError: boolean
  showModelsBillingError?: boolean
  skuFilter: string
  setSkuFilter: React.Dispatch<React.SetStateAction<string>>
  codingAgentEnabled: boolean
  sparkEnabled: boolean
}

export function BudgetProductSelector({
  products,
  skus,
  budgetType,
  budgetValue,
  setBudgetType,
  setBudgetValue,
  isUserRoute,
  showSkuError,
  showModelsBillingError,
  skuFilter,
  setSkuFilter,
  codingAgentEnabled,
  sparkEnabled,
}: Props) {
  const skuLevelBudgets = isFeatureEnabled('billing_sku_level_budgets')
  const premiumRequests = isFeatureEnabled('billingplatform_copilot_premium_sku')

  const productItems: ActionListItemInput[] = products
    .filter(product =>
      skus
        .filter(sku => premiumRequests || sku.sku !== CopilotPremiumRequestSku)
        .some(sku => sku.product === product.name),
    ) // Filter out products with no corresponding SKUs
    .map(product => ({
      text: PRODUCT_TAB_TEXT_MAP[product.name as Products],
      leadingVisual: (() => {
        const Icon = PRODUCT_TAB_ICON_MAP[product.name as Products] || MarkGithubIcon
        return <Icon size={16} />
      }) as React.FC,
      id: product.name,
    }))
    .sort((a, b) => a.text.localeCompare(b.text))

  const setSkuDescription = (sku: PricingDetails) => {
    if (sku && sku.sku === CopilotPremiumRequestSku) {
      if (codingAgentEnabled && sparkEnabled) {
        return 'Applies for Copilot, Spark, and Copilot coding agent usage.'
      } else if (codingAgentEnabled) {
        return 'Applies for Copilot and Copilot coding agent usage'
      } else if (sparkEnabled) {
        return 'Applies for Copilot and Spark usage'
      }
    }
    return undefined
  }

  const skuItems: ActionListItemInput[] = skus
    // TODO: this needs to be FF'd so it can be removed with the Premium Request launch
    .filter(sku => premiumRequests || sku.sku !== CopilotPremiumRequestSku)
    .map(sku => ({
      text: sku.friendlyName,
      id: sku.friendlyName,
      description: setSkuDescription(sku),
      descriptionVariant: 'block' as const,
    }))
    .sort((a, b) => a.text.localeCompare(b.text))

  const [selectedProduct, setSelectedProduct] = useState<ActionListItemInput>(productItems[0] || {text: ''})
  const [selectedSkus, setSelectedSkus] = useState<ActionListItemInput>({text: ''})

  const [productSelectorOpen, setProductSelectorOpen] = useState(false)
  const [skuSelectorOpen, setSkuSelectorOpen] = useState(false)

  const [filterProduct, setFilterProduct] = useState('')

  const filteredProductItems = productItems.filter(
    item => item.text === selectedProduct?.text || item.text?.toLowerCase().startsWith(filterProduct.toLowerCase()),
  )
  const selectedProductsSortedFirst = filteredProductItems.sort((a, b) => {
    if (a.text === selectedProduct?.text) return -1
    if (b.text === selectedProduct?.text) return 1
    return 0
  })

  const filteredSkus = skuItems.filter(item => {
    const skuProduct = skus.find(sku => sku.friendlyName === item.text)?.product
    const selectedProductName = Object.entries(PRODUCT_TAB_TEXT_MAP).find(
      ([_, value]) => value === selectedProduct?.text,
    )?.[0]
    const matchesSelectedProduct = skuProduct === selectedProductName

    // check if the search string appears anywhere in the item text
    const fuzzyMatches = !skuFilter || (item.text?.toLowerCase().includes(skuFilter.toLowerCase()) ?? false)

    // Only include SKUs that belong to the selected product AND meet the fuzzy match condition
    return matchesSelectedProduct && fuzzyMatches
  })
  const selectedSkuItemsSortedFirst = filteredSkus.sort((a, b) => {
    if (a.text === selectedSkus?.text) return -1
    if (b.text === selectedSkus?.text) return 1
    return 0
  })

  const handleProductSelection = (product: ActionListItemInput | undefined) => {
    if (!product) return
    setSelectedProduct(product)
    setBudgetValue(Object.entries(PRODUCT_TAB_TEXT_MAP).find(([_, value]) => value === product.text)?.[0] || '')
    setBudgetType('ProductPricing')
    setSelectedSkus({text: ''})
  }
  const handleProductSelectionForSkuPanel = (product: ActionListItemInput | undefined) => {
    if (!product) return
    setSelectedProduct(product)
    setSelectedSkus({text: ''})
    setBudgetValue('')
    setSkuFilter(product.text || '')
  }

  const handleSkuSelection = (sku: ActionListItemInput | undefined) => {
    if (!sku) return
    setSelectedSkus(sku)
    setBudgetValue(skus.find(s => s.friendlyName === sku.text)?.sku || '')
    setBudgetType('SkuPricing')
  }

  const findProductSubtext = () => {
    if (selectedProduct && selectedProduct.id === 'copilot') {
      if (codingAgentEnabled && sparkEnabled) {
        return 'The budget will apply only to Copilot premium requests (Copilot, Spark, and Copilot coding agent)'
      } else if (codingAgentEnabled) {
        return 'The budget will apply only to Copilot premium requests (Copilot and Copilot coding agent)'
      } else if (sparkEnabled) {
        return 'The budget will apply only to Copilot premium requests (Copilot and Spark)'
      }
      return 'The budget will apply only to Copilot premium requests'
    }
    return undefined
  }
  const productSubtext = findProductSubtext()

  const findSkuSubtext = () => {
    if (selectedSkus && selectedSkus.id === 'Copilot Premium Request') {
      if (codingAgentEnabled && sparkEnabled) {
        return 'The budget will apply for Copilot, Spark, and Copilot coding agent usage.'
      } else if (codingAgentEnabled) {
        return 'The budget will apply for Copilot and Copilot coding agent usage.'
      } else if (sparkEnabled) {
        return 'The budget will apply for Copilot and Spark usage.'
      }
    }
    return undefined
  }
  const skuSubtext = findSkuSubtext()

  return !skuLevelBudgets ? (
    <div>
      <Heading as="h2" className={styles.Heading}>
        Product
      </Heading>
      <RadioGroup
        name="budget-product-choices"
        aria-labelledby="budget-product-choices"
        onChange={selection => {
          if (selection) {
            setBudgetValue(selection)
          }
        }}
      >
        <div className={styles.BudgetSubTitleBox}>
          <span>Select the product to include in this budget.</span>
        </div>
        <div className="Box">
          {products.map(product => (
            <div key={product.name} className="Box-row">
              <FormControl disabled={product.name === 'copilot' && isUserRoute}>
                <Radio value={product.name} name="product" checked={budgetValue === product.name} />
                <FormControl.Label>{product.friendlyProductName}</FormControl.Label>
                {product.name === 'copilot' && isUserRoute && (
                  <FormControl.Caption>Not available for subscription plans</FormControl.Caption>
                )}
              </FormControl>
            </div>
          ))}
        </div>
      </RadioGroup>
    </div>
  ) : (
    <div>
      <Heading as="h2" className={styles.Heading} aria-label="Budget type">
        Budget type
      </Heading>
      <RadioGroup
        name="budget-product-choices"
        aria-labelledby="budget-product-choices"
        onChange={selection => {
          if (selection) {
            setBudgetType(selection)
            setBudgetValue(productItems[0]?.text || '') // Reset budgetValue when the radio button changes
            setSelectedProduct(productItems[0] || {text: ''})
            setSelectedSkus({text: ''})
            setSkuFilter(productItems[0]?.text || '')
          }
        }}
      >
        <div className={styles.BudgetSubTitleBox}>
          <span>Set budget for either a product or individual SKU within a product.</span>
        </div>
        <div className="Box">
          <div key="ProductPricing" className="Box-row">
            <FormControl className={styles.FlexContainerHorizontal}>
              <Radio value="ProductPricing" name="ProductPricing" checked={budgetType === 'ProductPricing'} />
              <FormControl.Label>
                Product-level budget
                {budgetType === 'ProductPricing' && (
                  <SelectPanelWrapper
                    label="Product"
                    showLabel={false}
                    showLeadingVisual
                    items={selectedProductsSortedFirst}
                    selected={selectedProduct}
                    onSelectedChange={handleProductSelection}
                    onFilterChange={setFilterProduct}
                    open={productSelectorOpen}
                    setOpen={setProductSelectorOpen}
                    placeholderText="Search"
                    title="Select 1 product"
                  />
                )}
                {budgetType === 'ProductPricing' && productSubtext && (
                  <p className={styles.BudgetSubtext}>{productSubtext}</p>
                )}
                {budgetValue === 'models' && showModelsBillingError && <ModelsBillingErrorMessage />}
              </FormControl.Label>
            </FormControl>
          </div>
          <div key="SkuPricing" className="Box-row">
            <FormControl className={styles.FlexContainerHorizontal}>
              <Radio value="SkuPricing" name="SkuPricing" checked={budgetType === 'SkuPricing'} />
              <FormControl.Label>
                SKU-level budget
                {budgetType === 'SkuPricing' && (
                  <>
                    <SelectPanelWrapper
                      label="Product"
                      showLabel
                      showLeadingVisual
                      items={selectedProductsSortedFirst}
                      selected={selectedProduct}
                      onSelectedChange={handleProductSelectionForSkuPanel}
                      onFilterChange={setFilterProduct}
                      open={productSelectorOpen}
                      setOpen={setProductSelectorOpen}
                      title="Select 1 product"
                      placeholderText="Search"
                    />
                    <SelectPanelWrapper
                      label="SKU"
                      showLabel
                      showLeadingVisual={false}
                      items={selectedSkuItemsSortedFirst}
                      selected={selectedSkus}
                      onSelectedChange={handleSkuSelection}
                      onFilterChange={setSkuFilter}
                      open={skuSelectorOpen}
                      setOpen={setSkuSelectorOpen}
                      placeholderText="Search"
                    />
                    {showSkuError && selectedSkus?.text === '' && (
                      <InlineMessage variant="critical" className={styles.SKUErrorInlineMessage}>
                        SKU is required
                      </InlineMessage>
                    )}
                    {skuSubtext && <p className={styles.BudgetSubtext}>{skuSubtext}</p>}
                    {skuFilter === 'Models' && showModelsBillingError && <ModelsBillingErrorMessage />}
                  </>
                )}
              </FormControl.Label>
            </FormControl>
          </div>
        </div>
      </RadioGroup>
    </div>
  )
}

import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
import {LinkedSkuSelectElement} from '../linked-sku-select-element'

describe('linked-sku-select-element', () => {
  let container: LinkedSkuSelectElement
  const testSkus = [
    {product: 'product1', sku: 'sku1', friendlyName: 'SKU 1'},
    {product: 'product1', sku: 'sku2', friendlyName: 'SKU 2'},
    {product: 'product2', sku: 'sku3', friendlyName: 'SKU 3'},
  ]

  beforeEach(async function () {
    container = await fixture(html`
      <linked-sku-select data-linked-sku-select-skus-value="${JSON.stringify(testSkus)}">
        <select data-target="linked-sku-select.product">
          <option value="product1">Product 1</option>
          <option value="product2">Product 2</option>
        </select>
        <select data-target="linked-sku-select.sku"></select>
      </linked-sku-select>
    `)
  })

  it('initializes with correct targets', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, LinkedSkuSelectElement)
    assert.ok(container.product, 'product select exists')
    assert.ok(container.sku, 'sku select exists')
  })

  it('loads SKUs for initial product selection', () => {
    const skuOptions = Array.from(container.sku.options)
    assert.equal(skuOptions.length, 2, 'should have 2 SKUs for product1')

    // Assert first option exists and has correct values
    assert(skuOptions[0], 'first option should exist')
    assert.equal(skuOptions[0].value, 'sku1')
    assert.equal(skuOptions[0].text, 'SKU 1')

    // Assert second option exists and has correct values
    assert(skuOptions[1], 'second option should exist')
    assert.equal(skuOptions[1].value, 'sku2')
    assert.equal(skuOptions[1].text, 'SKU 2')
  })

  it('updates SKU options when product changes', () => {
    container.product.value = 'product2'
    container.product.dispatchEvent(new Event('change'))

    const skuOptions = Array.from(container.sku.options)
    assert.equal(skuOptions.length, 1, 'should have 1 SKU for product2')

    // Assert option exists and has correct values
    assert(skuOptions[0], 'option should exist')
    assert.equal(skuOptions[0].value, 'sku3')
    assert.equal(skuOptions[0].text, 'SKU 3')
  })

  it('maintains selected SKU when product remains the same', () => {
    // Select a SKU first
    container.sku.value = 'sku2'

    // Trigger a product change to the same product
    container.product.value = 'product1'
    container.product.dispatchEvent(new Event('change'))

    assert.equal(container.sku.value, 'sku2', 'should maintain selected SKU')
  })

  it('clears SKU selection when switching to product without matching SKU', () => {
    // Select a SKU for product1
    container.sku.value = 'sku1'

    // Switch to product2
    container.product.value = 'product2'
    container.product.dispatchEvent(new Event('change'))

    assert.notEqual(container.sku.value, 'sku1', 'should clear previous SKU selection')
  })

  it('handles empty product selection', () => {
    container.product.value = ''
    container.product.dispatchEvent(new Event('change'))

    assert.equal(container.sku.options.length, 0, 'should have no SKU options')
  })
})

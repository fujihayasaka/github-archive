import {controller, target} from '@github/catalyst'

@controller
export class LinkedSkuSelectElement extends HTMLElement {
  @target declare product: HTMLSelectElement
  @target declare sku: HTMLSelectElement

  skus: Array<{product: string; sku: string; friendlyName: string}> = []

  connectedCallback() {
    if (this.product && this.sku) {
      this.initialize()
    } else {
      // Set up MutationObserver to wait for targets
      const observer = new MutationObserver(() => {
        if (this.product && this.sku) {
          observer.disconnect()
          this.initialize()
        }
      })

      observer.observe(this, {childList: true, subtree: true})
    }
  }

  initialize() {
    // Parse SKUs data
    const skusData = this.getAttribute('data-linked-sku-select-skus-value')
    if (skusData) this.skus = JSON.parse(skusData)

    // Add change listener
    this.product.addEventListener('change', () => this.updateSkus())

    // Initial population
    this.updateSkus()
  }

  updateSkus() {
    const product = this.product.value
    const currentValue = this.sku.value
    this.sku.textContent = ''

    if (!product) return

    // Add SKUs that match selected product
    const filteredSkus = this.skus.filter(sku => sku.product === product)
    for (const sku of filteredSkus) {
      this.sku.add(new Option(sku.friendlyName, sku.sku))
    }

    // Restore previously selected value if it exists in the new options
    if (currentValue && filteredSkus.some(sku => sku.sku === currentValue)) {
      this.sku.value = currentValue
    }
  }
}

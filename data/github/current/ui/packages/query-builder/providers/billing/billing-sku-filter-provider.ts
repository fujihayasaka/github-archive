import type {QueryBuilderElement} from '@github-ui/query-builder-element'
import {
  FetchDataEvent,
  FilterItem,
  type FilterProvider,
  type QueryEvent,
} from '@github-ui/query-builder-element/query-builder-api'
import {hasMatch} from 'fzy.js'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

type SKUData = {
  sku: string
  product: string
}

type SKUAPIResponse = {
  skus: SKUData[]
}

export class BillingSKUFilterProvider extends EventTarget implements FilterProvider {
  type = 'filter' as const
  name: string
  slug: string
  priority: number
  singularItemName: string
  value: string
  isOrgRoute: boolean
  isUserRoute: boolean

  skuCache: SKUData[] | undefined = undefined
  enabledProducts?: string[]

  constructor(
    queryBuilder: QueryBuilderElement,
    {
      name,
      slug,
      value,
      priority,
      isOrgRoute = false,
      isUserRoute = false,
      enabledProducts,
    }: {
      name: string
      slug: string
      value: string
      priority: number
      isOrgRoute: boolean
      isUserRoute: boolean
      enabledProducts?: string[]
    },
  ) {
    super()

    this.name = name
    this.slug = slug
    this.singularItemName = name
    this.value = value
    this.priority = priority
    this.isOrgRoute = isOrgRoute
    this.isUserRoute = isUserRoute
    this.enabledProducts = enabledProducts
    queryBuilder.addEventListener('query', this)
    queryBuilder.attachProvider(this)
  }

  async handleEvent(event: QueryEvent) {
    const lastElement = event.parsedQuery.at(-1)!

    if (
      (lastElement.value !== '' || this.priority <= 5) &&
      lastElement?.type !== 'filter' &&
      !event.parsedQuery.some(e => e.type === 'filter' && e.filter === this.value) &&
      (hasMatch(lastElement?.value, this.name) || hasMatch(lastElement?.value, this.value))
    ) {
      this.dispatchEvent(new Event('show'))
    }

    if (lastElement?.type !== this.type || lastElement.filter !== this.value) return

    if (!this.skuCache) {
      // Immediately set this to avoid multiple requests
      this.skuCache = []
      const fetchPromise = this.fetchTopSKUs(event)
      this.dispatchEvent(new FetchDataEvent(fetchPromise))
    } else {
      for (const sku of this.skuCache) {
        this.emitSuggestion(sku.sku, sku.sku, lastElement.value)
      }
    }
  }

  async fetchTopSKUs(event: QueryEvent) {
    let skuData: SKUAPIResponse
    let url: string
    try {
      if (this.isOrgRoute) {
        url = `/organizations/${this.slug}/settings/billing/skus`
      } else if (this.isUserRoute) {
        url = `/settings/billing/skus`
      } else {
        url = `/enterprises/${this.slug}/billing/skus`
      }
      const response = await verifiedFetchJSON(url, {method: 'GET'})
      if (response.status !== 200) {
        this.skuCache = undefined
        return
      }

      skuData = await response.json()
      if (!skuData?.skus) return

      // Filter SKUs based on enabled products
      const enabledSkus = !this.enabledProducts?.length
        ? skuData.skus
        : skuData.skus.filter(sku => {
            // Convert both strings to lowercase and remove spaces/underscores for comparison
            const normalizeString = (str: string) => str.toLowerCase().replace(/[\s-]/g, '_')
            const skuProduct = normalizeString(sku.product)
            return this.enabledProducts!.some(enabledProduct => {
              const normalizedProduct = normalizeString(enabledProduct)
              return skuProduct === normalizedProduct
            })
          })

      // Cache the filtered SKUs
      this.skuCache = enabledSkus

      // Emit suggestions for filtered SKUs
      const query = event.parsedQuery.at(-1)!.value
      for (const skuResult of enabledSkus) {
        this.emitSuggestion(skuResult.sku, skuResult.sku, query)
      }
    } catch {
      this.skuCache = undefined
      return
    }
  }

  private emitSuggestion(name: string, value: string, query: string): void {
    if (query && !hasMatch(query, value)) return

    this.dispatchEvent(
      new FilterItem({
        filter: this.value,
        value,
        name,
      }),
    )
  }
}

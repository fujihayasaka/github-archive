import type {QueryBuilderElement} from '@github-ui/query-builder-element'
import {
  FetchDataEvent,
  FilterItem,
  type FilterProvider,
  type QueryEvent,
} from '@github-ui/query-builder-element/query-builder-api'
import {hasMatch} from 'fzy.js'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

type ProductData = {
  name: string
  friendlyProductName: string
}

type ProductAPIResponse = {
  products: ProductData[]
}

export class BillingProductFilterProvider extends EventTarget implements FilterProvider {
  type = 'filter' as const
  name: string
  slug: string
  priority: number
  singularItemName: string
  value: string
  isOrgRoute: boolean
  isUserRoute: boolean

  productCache: ProductData[] | undefined = undefined
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

    if (!this.productCache) {
      // Immediately set this to avoid multiple requests
      this.productCache = []
      const fetchPromise = this.fetchTopProducts(event)
      this.dispatchEvent(new FetchDataEvent(fetchPromise))
    } else {
      for (const product of this.productCache) {
        this.emitSuggestion(product.friendlyProductName, product.name, lastElement.value)
      }
    }
  }

  async fetchTopProducts(event: QueryEvent) {
    let productData: ProductAPIResponse
    let url: string
    try {
      if (this.isOrgRoute) {
        url = `/organizations/${this.slug}/settings/billing/products`
      } else if (this.isUserRoute) {
        url = `/settings/billing/products`
      } else {
        url = `/enterprises/${this.slug}/billing/products`
      }
      const response = await verifiedFetchJSON(url, {method: 'GET'})

      if (response.status !== 200) {
        // If we have an error, we don't want to cache the results, such that we can retry later.
        this.productCache = undefined
        return
      }

      productData = await response.json()
    } catch {
      // If we have an error, we don't want to cache the results, such that we can retry later.
      this.productCache = undefined
      return
    }

    const query = event.parsedQuery.at(-1)!.value

    // If options are empty or undefined, just display all products
    if (!this.enabledProducts?.length) {
      for (const productResult of productData['products'] || []) {
        this.productCache!.push({...productResult})
        this.emitSuggestion(productResult.friendlyProductName, productResult.name, query)
      }
    } else {
      // Filter products based on enabled options
      for (const productResult of productData['products'] || []) {
        const matchedOption = this.enabledProducts?.find(product =>
          this.matchesOption(productResult.friendlyProductName, product),
        )

        if (matchedOption) {
          this.productCache!.push({...productResult})
          this.emitSuggestion(productResult.friendlyProductName, productResult.name, query)
        }
      }
    }
  }

  emitSuggestion(name: string, value: string, query: string) {
    if (query && !hasMatch(query, value)) return

    this.dispatchEvent(
      new FilterItem({
        filter: this.value,
        value,
        name,
      }),
    )
  }

  private matchesOption(productName: string, option: string): boolean {
    const normalizedProductName = productName.toLowerCase()
    const normalizedOption = option.toLowerCase()

    // Try direct match first
    if (normalizedProductName === normalizedOption) {
      return true
    }

    // Try matching with normalized format (spaces to underscores)
    const productNameUnderscored = normalizedProductName.replace(/\s+/g, '_')
    const optionUnderscored = normalizedOption.replace(/\s+/g, '_')

    return productNameUnderscored === optionUnderscored
  }
}

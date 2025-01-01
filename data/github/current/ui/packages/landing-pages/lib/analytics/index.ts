type MarketingAnalyticsEventAttrs = {
  action: string
  tag: string
  context: string
  location: string
}

// Adds "data-analytics-event" attribute to elements for tracking
export function analyticsEvent({action, tag, context, location}: MarketingAnalyticsEventAttrs) {
  return {
    'data-analytics-event': JSON.stringify({
      action,
      tag,
      context,
      location,
      label: `${action}_${tag}_${context}_${location}`,
    }),
  }
}

export function cohortFunnelBuilder(cft: string) {
  return (path?: string, options?: {product?: string}): string => {
    if (!path) return ''
    return injectCohortFunnelParams(path, cft, options?.product)
  }
}

function injectCohortFunnelParams(path: string, cft: string, product?: string): string {
  const [root, queryString] = path.split('?')
  const pathParams = new URLSearchParams(queryString)

  if (product) {
    pathParams.set('cft', `${cft}.${product}`)
  } else {
    pathParams.set('cft', cft)
  }

  if (pathParams.has('return_to')) {
    const returnTo = pathParams.get('return_to')
    const decodedReturnTo = decodeURIComponent(returnTo || '')
    const returnToWithCohortFunnel = injectCohortFunnelParams(decodedReturnTo, cft, product)
    pathParams.set('return_to', returnToWithCohortFunnel)
  }

  return `${root}?${pathParams.toString()}`
}

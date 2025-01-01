import {type Variables, type GraphQLResponse, stableCopy, type GraphQLResponseWithoutData} from 'relay-runtime'
import type {Sink} from 'relay-runtime/lib/network/RelayObservable'
import {getInsightsUrl, reportTraceData} from '@github-ui/internal-api-insights'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
// eslint-disable-next-line no-restricted-imports
import {reportError} from '@github-ui/failbot'
import {ALLOWED_ERRORS, CONDITIONAL_ALLOWED_ERRORS} from './constants/values'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {getBaseFetchHeaders} from '@github-ui/fetch-headers'
import {checkConditionalAllowedPaths} from './helpers'

type Json = string | number | boolean | null | {[property: string]: Json} | Json[]

type JsonRoot = {[property: string]: Json}

export type GraphQLError = {type: string; message: string; path: Array<string | number>}
type GraphQLSuccessfulResult = {
  data: JsonRoot
  timestamp?: number
  extensions?: Record<string, Record<string, JsonRoot>>
}
type GraphQLErrorResult = {
  errors: GraphQLError[]
  data?: JsonRoot
  timestamp?: number
  extensions: Record<string, string>
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type ErrorTypeCallbacks = Record<string, (params?: any) => void>
export type ErrorCallbacks = Record<number, ErrorTypeCallbacks>

export const IssuesShowRegex = new RegExp(/^\/[\w-_]*\/[\w-_]*\/issues\/\d*$/)

export type GraphQLResult = GraphQLSuccessfulResult | GraphQLErrorResult
export type GraphQLSubscriptionResult = {subscriptionId: string | null; response: GraphQLResponse}

function validateNoErrors(
  decoded: GraphQLResult,
  requestId: string,
  persistedQueryId: string,
  observer?: Sink<GraphQLResponse>,
): GraphQLSuccessfulResult {
  removeAllowedErrors(requestId, decoded)
  if ('errors' in decoded && decoded.errors.length) {
    const formatted = decoded.errors
      .map(error => `GraphQL error: ${error.type}: ${error.message} (path: ${error.path})`)
      .join(', ')
    const error = new ValidationError(
      `${formatted} (Persisted query id: ${persistedQueryId})`,
      {cause: decoded.errors},
      decoded.extensions?.query_owning_catalog_service,
    )
    if (observer) {
      reportError(error)
      observer.error(error)
    } else {
      throw error
    }
  }
  if (!('data' in decoded)) {
    const error = new Error(
      `Expected data property in response: ${JSON.stringify(
        decoded,
      )}. persistedQueryId: ${persistedQueryId}, requestId: ${requestId}`,
    )
    if (observer) {
      reportError(error)
      observer.error(error)
    } else {
      throw error
    }
  }
  return decoded as GraphQLSuccessfulResult
}

class ValidationError extends Error {
  catalogService: string | undefined
  constructor(message: string, options: ErrorOptions, catalogService?: string) {
    super(message, options)
    this.catalogService = catalogService
    this.name = 'ValidationError'
  }
}

async function assertNoHttpErrors(
  response: Response,
  persistedQueryId: string,
  persistedQueryName: string,
): Promise<void> {
  // 404 is handled by GraphQL
  // 401 is caused by a forbidden anonymous query, which is reported to datadog
  if (response.status > 401 && response.status !== 404) {
    const text = await response.text()
    const errorInfo = {
      url: response.url,
      timestamp: new Date().toISOString(),
      persistedQueryId,
      persistedQueryName,
      failureRequestId: response.headers.get('X-Github-Request-Id'),
    }

    const errorDetails = `HTTP error (${response.status}): ${text ? text : 'No additional text'}.
    Error Info: ${JSON.stringify(errorInfo)}`

    throw new Error(errorDetails, {cause: response.status})
  }
}

function removeAllowedErrors(requestId: string, decoded: GraphQLResult): GraphQLResult {
  if ('errors' in decoded) {
    decoded.errors
      .filter(
        error =>
          ALLOWED_ERRORS.includes(error.type) ||
          !!CONDITIONAL_ALLOWED_ERRORS[error.type]?.includes(error.message) ||
          checkConditionalAllowedPaths(error.type, error.path),
      )
      .map(error => {
        // eslint-disable-next-line no-console
        console.error(
          `Failed to fetch data. Please use this request ID when contacting support: ${requestId} Error: ${error.type}: ${error.message} (path: ${error.path})`,
        )
      })

    decoded.errors = decoded.errors.filter(
      error =>
        !ALLOWED_ERRORS.includes(error.type) &&
        !CONDITIONAL_ALLOWED_ERRORS[error.type]?.includes(error.message) &&
        !checkConditionalAllowedPaths(error.type, error.path),
    )
  }
  return decoded
}

// Fetch GraphQL from the server and return a decoded result.
export default async function fetchGraphQL(
  persistedQueryId: string,
  persistedQueryName: string,
  variables: Variables,
  method: 'GET' | 'POST' = 'GET',
  baseUrl?: string,
  enabledFeatures?: {[key: string]: boolean},
  errorCallbacks?: ErrorCallbacks,
  observer?: Sink<GraphQLResponse>,
): Promise<GraphQLResponse> {
  const result = await fetchGraphQLWithSubscription(
    persistedQueryId,
    persistedQueryName,
    variables,
    method,
    {
      isSubscription: false,
      scope: undefined,
    },
    baseUrl,
    enabledFeatures,
    errorCallbacks,
    observer,
  )
  return result.response
}

// Fetch GraphQL from the server and return a response promise along with an
// optional subscriptionId if the query is a subscription.
export async function fetchGraphQLWithSubscription(
  persistedQueryId: string,
  persistedQueryName: string,
  variables: Variables,
  method: 'GET' | 'POST' = 'POST',
  options: {
    isSubscription?: boolean
    subscriptionTopic?: string
    dispatchTime?: number
    scopeObject?: Record<string, unknown>
    scope?: string
  } = {},
  baseUrl?: string,
  enabledFeatures?: {[key: string]: boolean},
  errorCallbacks?: ErrorCallbacks,
  observer?: Sink<GraphQLResponse>,
): Promise<GraphQLSubscriptionResult> {
  const canonicalizedPayload = JSON.stringify(
    // stableCopy will alphabetize the keys in the variable payload.
    // Necessary to ensure a match against early-hinted/preloaded requests.
    stableCopy({
      query: persistedQueryId,
      variables,
      ...(options.scopeObject ? {scopeObject: options.scopeObject} : {}),
    }),
  )

  const {isSubscription, scope, subscriptionTopic, dispatchTime} = options

  const nonReportingRelayGraphqlStatusCodesEnabled = isFeatureEnabled('nonreporting_relay_graphql_status_codes')

  const url = constructUrl(
    method,
    encodeURIComponent(canonicalizedPayload),
    isSubscription,
    subscriptionTopic,
    scope,
    dispatchTime,
    baseUrl,
  )
  let subscriptionId = null

  try {
    const {
      subscriptionId: currentSubscriptionId,
      requestId,
      json,
      status,
    } = await getGraphQLQuery(url, method, persistedQueryId, persistedQueryName, canonicalizedPayload, enabledFeatures)
    subscriptionId = currentSubscriptionId
    if (errorCallbacks && json.errors) {
      const callbacks = errorCallbacks[status]
      if (callbacks) {
        for (const error of json.errors) {
          const callback = callbacks[error.type]
          callback?.({persistedQueryName, errorMessage: error.message})
        }
      }
    }
    const cleaned = validateNoErrors(json as GraphQLResult, requestId, persistedQueryId, observer)
    if (cleaned) {
      reportTraceData(cleaned)
    }
    return {subscriptionId, response: cleaned}
  } catch (error) {
    if (observer) {
      const shouldNotReportError = nonReportingRelayGraphqlStatusCodesEnabled && (error as Error).cause === 429
      if (!shouldNotReportError) {
        reportError(error)
      }
      observer.error(error as Error)
      const errorResponse = {
        errors: [{message: 'An error occurred while fetching data. Please try again later.'}],
        extensions: {},
      } as GraphQLResponseWithoutData
      return {subscriptionId, response: errorResponse}
    } else {
      throw error
    }
  }
}

function constructUrl(
  method: 'GET' | 'POST',
  content: string,
  isSubscription?: boolean,
  subscriptionTopic?: string,
  scope?: string,
  dispatchTime?: number,
  baseUrl = '/_graphql',
) {
  const queryParameters = []
  if (method === 'GET') {
    queryParameters.push(`body=${content}`)
  }
  if (isSubscription) {
    queryParameters.push('subscription=1')
  }
  if (scope) {
    queryParameters.push(`scope=${encodeURIComponent(scope)}`)
  }
  if (subscriptionTopic) {
    queryParameters.push(`subscriptionTopic=${encodeURIComponent(subscriptionTopic)}`)
  }
  if (dispatchTime) {
    queryParameters.push(`dispatchTime=${encodeURIComponent(dispatchTime)}`)
  }

  // grab and forward any feature flags from the URL
  if (ssrSafeWindow) {
    const url = new URL(ssrSafeWindow.location.href, ssrSafeWindow.location.origin)
    const features = url.searchParams.get('_features')
    if (features) {
      queryParameters.push(`_features=${features}`)
    }
  }

  return queryParameters.length > 0 ? `${baseUrl}?${queryParameters.join('&')}` : baseUrl
}

async function getGraphQLQuery(
  url: string,
  method: string,
  persistedQueryId: string,
  persistedQueryName: string,
  body?: string,
  enabledFeatures?: {[key: string]: boolean},
) {
  const effectiveUrl = getInsightsUrl(url)
  return getGraphQLData(effectiveUrl, method, persistedQueryId, persistedQueryName, body, enabledFeatures)
}

async function getGraphQLData(
  url: string,
  method: string,
  persistedQueryId: string,
  persistedQueryName: string,
  body?: string,
  enabledFeatures?: {[key: string]: boolean},
) {
  let httpResponse: Response

  const bodyInit = body ? {body} : undefined

  const headers: {[key: string]: string} = {
    ...getBaseFetchHeaders(),
  }
  if (enabledFeatures?.issues_react_perf_test) {
    headers['X-LUC-Environment'] = 'issues'
  }

  if (method === 'GET') {
    httpResponse = await fetch(url, {
      method,
      cache: 'no-cache',
      credentials: 'include',
      headers,
    })
  } else {
    httpResponse = await verifiedFetch(url, {
      method,
      headers: {
        Accept: 'application/json',
        ...headers,
      },
      ...bodyInit,
    })
  }

  await assertNoHttpErrors(httpResponse, persistedQueryId, persistedQueryName)
  const json = await httpResponse.json()
  const subscriptionId = httpResponse.headers.get('X-Subscription-ID')
  const requestId = httpResponse.headers.get('X-Github-Request-Id') || ''
  const status = httpResponse.status

  return {subscriptionId, requestId, json, status}
}

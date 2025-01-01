import {Pagination, Link} from '@primer/react'
import {Subhead} from '../components/Subhead'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {BypassRequestsRoutePayload, ExemptionRequest} from '../delegated-bypass-types'
import {DelegatedBypassRow} from '../components/DelegatedBypassRow'
import {useRelativeNavigation} from '../hooks/use-relative-navigation'
import {BypassRequestsFilterBar} from '../components/BypassRequestsFilterBar'
import {requestsIndexPath} from '../helpers/requests-filter'
import {BypassRequestsBlank} from '../components/BypassRequestsBlank'
import {componentRegistry} from '../components/RequestForm/index'
import {useRequestTypeContext} from '../contexts/RequestTypeContext'
import {useIsStafftools} from '../hooks/use-is-stafftools'

export function BypassRequestsPage() {
  return <BypassRequestsComponent />
}

function BypassRequestsComponent() {
  const {exemptionRequests, filter, sourceType, repositories, organizations, hasMoreRequests, baseExemptionUrl} =
    useRoutePayload<BypassRequestsRoutePayload>()
  const {navigate} = useRelativeNavigation()
  const requestType = useRequestTypeContext()
  const {bypassRequestListHeader, bypassRequestListSubheader} = componentRegistry({requestType})
  const isStafftools = useIsStafftools()

  const getBaseExemptionUrl = (exemptionRequest: ExemptionRequest) => {
    if (sourceType === 'repository') {
      return baseExemptionUrl
    }
    return isStafftools
      ? `/stafftools/repositories${exemptionRequest.repoExemptionsBaseUrl}`
      : exemptionRequest.repoExemptionsBaseUrl
  }

  let {page} = filter
  page = page || 1
  const pageCount = hasMoreRequests ? page + 1 : page

  return (
    <>
      <Subhead heading={bypassRequestListHeader} />
      <div className="mb-2">
        <span className="text-normal color-fg-muted">{bypassRequestListSubheader}</span>{' '}
        {requestType === 'secret_scanning' && (
          <Link href="https://docs.github.com/en/enterprise-cloud@latest/code-security/secret-scanning/using-advanced-secret-scanning-and-push-protection-features/delegated-bypass-for-push-protection/about-delegated-bypass-for-push-protection">
            Learn more about delegated bypass
          </Link>
        )}
      </div>
      <BypassRequestsFilterBar
        filter={filter}
        sourceType={sourceType}
        repositories={repositories}
        organizations={organizations}
      />
      {exemptionRequests.length > 0 ? (
        <ol className="d-flex flex-column rounded-2 overflow-hidden color-bg-default border color-border-default color-fg-default position-relative ml-0">
          {exemptionRequests.map(exemptionRequest => (
            <DelegatedBypassRow
              key={exemptionRequest.id}
              exemptionRequest={exemptionRequest}
              baseExemptionUrl={getBaseExemptionUrl(exemptionRequest)}
            />
          ))}
        </ol>
      ) : (
        <div className="d-flex flex-column rounded-2 overflow-hidden color-bg-default border color-border-default mt-2">
          <BypassRequestsBlank requestType={requestType} />
        </div>
      )}
      {(page !== 1 || pageCount !== 1) && (
        <Pagination
          pageCount={pageCount}
          currentPage={page}
          onPageChange={(e, newPage) => {
            e.preventDefault()
            if (page !== newPage) {
              navigate('.', requestsIndexPath({filter: {...filter, page: newPage}}), true)
            }
          }}
          showPages={false}
        />
      )}
    </>
  )
}

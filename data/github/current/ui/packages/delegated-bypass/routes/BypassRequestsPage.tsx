import {Box, Text, Pagination} from '@primer/react'
import {Subhead} from '../components/Subhead'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {BypassRequestsRoutePayload} from '../delegated-bypass-types'
import {DelegatedBypassRow} from '../components/DelegatedBypassRow'
import {useRelativeNavigation} from '../hooks/use-relative-navigation'
import {BypassRequestsFilterBar} from '../components/BypassRequestsFilterBar'
import {requestsIndexPath} from '../helpers/requests-filter'
import {BypassRequestsBlank} from '../components/BypassRequestsBlank'
import {componentRegistry} from '../components/RequestForm/index'
import {useRequestTypeContext} from '../contexts/RequestTypeContext'

export function BypassRequestsPage() {
  return <BypassRequestsComponent />
}

function BypassRequestsComponent() {
  const {exemptionRequests, filter, sourceType, repositories, organizations, hasMoreRequests, baseExemptionUrl} =
    useRoutePayload<BypassRequestsRoutePayload>()
  const {navigate} = useRelativeNavigation()
  const requestType = useRequestTypeContext()
  const {bypassRequestListHeader, bypassRequestListSubheader} = componentRegistry({requestType})

  let {page} = filter
  page = page || 1
  const pageCount = hasMoreRequests ? page + 1 : page

  return (
    <>
      <Subhead heading={bypassRequestListHeader} beta={requestType !== 'secret_scanning'} />
      <Box sx={{mb: 2}}>
        <Text sx={{fontWeight: 'normal', color: 'fg.muted'}} as="span">
          {bypassRequestListSubheader}
        </Text>
      </Box>
      <BypassRequestsFilterBar
        filter={filter}
        sourceType={sourceType}
        repositories={repositories}
        organizations={organizations}
      />
      {exemptionRequests.length > 0 ? (
        <Box
          as="ol"
          sx={{
            display: 'flex',
            flexDirection: 'column',
            borderRadius: 2,
            overflow: 'hidden',
            backgroundColor: 'canvas.default',
            borderColor: 'border.default',
            borderStyle: 'solid',
            borderWidth: 1,
            color: 'fg.default',
            position: 'relative',
            ml: 0,
          }}
        >
          {exemptionRequests.map(exemptionRequest => (
            <DelegatedBypassRow
              key={exemptionRequest.id}
              exemptionRequest={exemptionRequest}
              baseExemptionUrl={sourceType === 'repository' ? baseExemptionUrl : exemptionRequest.repoExemptionsBaseUrl}
              displayRepoName={sourceType === 'organization' && exemptionRequest.requestType === 'secret_scanning'}
            />
          ))}
        </Box>
      ) : (
        <Box
          sx={{
            display: 'flex',
            flexDirection: 'column',
            borderRadius: 2,
            overflow: 'hidden',
            borderColor: 'border.default',
            borderStyle: 'solid',
            borderWidth: 1,
            marginTop: 2,
          }}
        >
          <BypassRequestsBlank />
        </Box>
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

import {useMemo} from 'react'
import {RelativeTime} from '@primer/react'
import {BlockedIcon} from '@primer/octicons-react'
import type {ExemptionResponse, ExemptionRequest, Ruleset} from '../delegated-bypass-types'
import {PendingRulesetResponseStatusLine, RequestStatusLine, RulesetResponseStatusLine, StatusLine} from './StatusLine'
import {pluralize} from '../helpers/string'

export function RequestState({
  request,
  responses,
  rulesets,
  isRequester,
  reviewerLogin,
}: {
  request: ExemptionRequest
  responses: ExemptionResponse[]
  rulesets?: Ruleset[]
  isRequester: boolean
  reviewerLogin?: string
}) {
  const statuses = useMemo(
    () =>
      rulesets?.map(ruleset => {
        const rulesetResponses = responses.filter(({rulesetIds}) => rulesetIds?.includes(ruleset.id))
        const response = rulesetResponses[rulesetResponses.length - 1]
        return {
          ruleset,
          response,
        }
      }) || [],
    [rulesets, responses],
  )
  const mostRecentTimestamp = useMemo(
    () =>
      responses
        .map(({updatedAt}) => new Date(updatedAt))
        .reduce((a, b) => (a > b ? a : b), new Date(request.createdAt))
        .toUTCString(),
    [responses, request],
  )
  const isRequestPending = request.status === 'pending'
  const finalTimestamp = useMemo(() => {
    let timestamp = mostRecentTimestamp ?? ''
    if (request.status === 'expired') {
      timestamp = request.expiresAt ?? timestamp
    }
    if (request.status === 'cancelled') {
      timestamp = request.updatedAt
    }
    return timestamp
  }, [mostRecentTimestamp, request])

  return (
    <div className="width-full mt-4">
      <div className="my-4 d-flex flex-column flex-items-center">
        <div className="width-full d-flex flex-column gap-3">
          {request.requestType === 'repository_policy_ruleset_bypass' && (
            <div className="d-flex flex-column gap-2">
              <StatusLine iconInfo={{icon: BlockedIcon, color: 'color-fg-subtle'}}>
                Blocked by {pluralize(rulesets?.length || 1, 'policy', 'policies')}
                <RelativeTime datetime={request.createdAt} />
                {rulesets ? <StatusLine.Rules rulesets={rulesets} /> : null}
              </StatusLine>
            </div>
          )}
          <RequestStatusLine
            requestStatus="pending"
            timestamp={request.createdAt}
            hideAction={!isRequester || !isRequestPending}
            changedRulesets={request.changedRulesets}
            requesterComment={request.requesterComment}
            requester={request.requester}
          />
          {responses.map(response => (
            <RulesetResponseStatusLine
              key={`response-${response.id}`}
              response={response}
              rulesets={rulesets?.filter(ruleset => response.rulesetIds?.includes(ruleset.id)) || []}
              reviewerLogin={reviewerLogin}
              requestStatus={request.status}
            />
          ))}
          {statuses.map(
            ({ruleset, response}) =>
              !response && (
                <PendingRulesetResponseStatusLine
                  key={`ruleset-${ruleset.id}`}
                  ruleset={ruleset}
                  hideAction={!isRequestPending}
                />
              ),
          )}
          {!isRequestPending ? (
            <RequestStatusLine
              requestStatus={request.status}
              timestamp={finalTimestamp}
              hideAction={!isRequester}
              changedRulesets={request.changedRulesets}
            />
          ) : null}
        </div>
      </div>
    </div>
  )
}

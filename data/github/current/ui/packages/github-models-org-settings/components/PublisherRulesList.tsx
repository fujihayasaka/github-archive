import {ActionList} from '@primer/react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {AccessPolicyShowPayload} from '../types'
import {useOrganizationAccessPolicy} from '../contexts/OrganizationAccessPolicyContext'
import {PublisherRule} from './PublisherRule'
import {usePublishers} from '../contexts/PublishersContext'

export function PublisherRulesList() {
  const {publishers} = useRoutePayload<AccessPolicyShowPayload>()
  const {isAllowlist} = useOrganizationAccessPolicy()
  const {allowedPublisherIds, blockedPublisherIds} = usePublishers()

  if ((isAllowlist && allowedPublisherIds.size < 1) || (!isAllowlist && blockedPublisherIds.size < 1)) {
    return (
      <div className="Box-body">
        <h3 className="py-5 text-center">
          No publishers have been <span>{isAllowlist ? 'allowed' : 'blocked'}</span> yet.
        </h3>
      </div>
    )
  }

  return (
    <ActionList className="Box-body px-0" aria-label="Publisher rules">
      {publishers.map(publisher =>
        (isAllowlist && allowedPublisherIds.has(publisher.id)) ||
        (!isAllowlist && blockedPublisherIds.has(publisher.id)) ? (
          <PublisherRule publisher={publisher} key={publisher.id} />
        ) : null,
      )}
    </ActionList>
  )
}

import {useState} from 'react'
import {UnderlineNav} from '@primer/react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {AccessPolicyShowPayload} from '../types'
import {ModelRulesList} from './ModelRulesList'
import {RuleListTypeToggle} from './RuleListTypeToggle'
import {PublisherRulesList} from './PublisherRulesList'
import {useOrganizationAccessPolicy} from '../contexts/OrganizationAccessPolicyContext'
import {usePublishers} from '../contexts/PublishersContext'

export function RulesTable() {
  const {models} = useRoutePayload<AccessPolicyShowPayload>()
  const {allowedPublisherIds, blockedPublisherIds} = usePublishers()
  const {allowedModelKeys, isAllowlist, isModelsEnabled} = useOrganizationAccessPolicy()
  const totalAffectedPublishers = isAllowlist ? allowedPublisherIds.size : blockedPublisherIds.size
  const totalAffectedModels = isAllowlist ? allowedModelKeys.size : models.length - allowedModelKeys.size
  const [isPublishersTabActive, setIsPublishersTabActive] = useState(
    totalAffectedPublishers > 0 || totalAffectedModels < 1,
  )
  const listNamePrefix = isAllowlist ? 'Allowed' : 'Blocked'

  if (!isModelsEnabled) return null

  return (
    <>
      <div className="mb-3 d-md-flex flex-row flex-justify-between flex-items-center">
        <RuleListTypeToggle />
      </div>
      <div className="Box Box--condensed">
        <UnderlineNav aria-label="View selected publishers or models">
          <UnderlineNav.Item
            as="button"
            aria-current={isPublishersTabActive ? 'location' : undefined}
            onSelect={() => setIsPublishersTabActive(true)}
            counter={totalAffectedPublishers}
          >
            {listNamePrefix} publishers
          </UnderlineNav.Item>
          <UnderlineNav.Item
            as="button"
            aria-current={!isPublishersTabActive ? 'location' : undefined}
            onSelect={() => setIsPublishersTabActive(false)}
            counter={totalAffectedModels}
          >
            {listNamePrefix} models
          </UnderlineNav.Item>
        </UnderlineNav>
        {isPublishersTabActive ? <PublisherRulesList /> : <ModelRulesList />}
      </div>
    </>
  )
}

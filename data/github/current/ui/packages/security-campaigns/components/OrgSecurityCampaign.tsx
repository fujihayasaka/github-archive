import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {OrgDraftSecurityCampaign} from './OrgDraftSecurityCampaign'
import {OrgPublishedSecurityCampaign} from './OrgPublishedSecurityCampaign'
import type {OrgSecurityCampaignPayload} from '../types/org-security-campaign-payload'

export function OrgSecurityCampaign() {
  const payload = useRoutePayload<OrgSecurityCampaignPayload>()
  const isDraft = !payload.campaign.publishedAt

  if (isDraft) {
    return <OrgDraftSecurityCampaign payload={payload} />
  }

  return <OrgPublishedSecurityCampaign payload={payload} />
}

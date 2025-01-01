import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {OrgSecurityCampaignPayload} from '../types/org-security-campaign-payload'
import {OrgDraftSecurityCampaign} from '../components/OrgDraftSecurityCampaign'
import {OrgPublishedSecurityCampaign} from '../components/OrgPublishedSecurityCampaign'

export function OrgSecurityCampaignShow() {
  const payload = useRoutePayload<OrgSecurityCampaignPayload>()
  const isDraft = !payload.campaign.publishedAt

  if (isDraft) {
    return <OrgDraftSecurityCampaign payload={payload} />
  }

  return <OrgPublishedSecurityCampaign payload={payload} />
}

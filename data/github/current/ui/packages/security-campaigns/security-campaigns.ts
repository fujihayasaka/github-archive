import {App} from './App'
import {RepositorySecurityCampaignShow} from './routes/RepositorySecurityCampaignShow'
import {OrgSecurityCampaignShow} from './routes/OrgSecurityCampaignShow'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {ClosedSecurityCampaigns} from './routes/ClosedSecurityCampaigns'
import {OrgSecurityCampaignsIndex} from './routes/OrgSecurityCampaignsIndex'
import {OrgSecurityCampaignNew} from './routes/OrgSecurityCampaignNew'
import {OrgDraftSecurityCampaignPublish} from './routes/OrgDraftSecurityCampaignPublish'
import {OrgSecurityCampaignPublish} from './routes/OrgSecurityCampaignPublish'

registerNavigatorApp('security-campaigns', () => ({
  App,
  routes: [
    jsonRoute({path: '/:owner/:repo/security/campaigns', Component: OrgSecurityCampaignsIndex}),
    jsonRoute({path: '/orgs/:owner/security/campaigns/new', Component: OrgSecurityCampaignNew}),
    jsonRoute({path: '/:owner/:repo/security/campaigns/:number', Component: RepositorySecurityCampaignShow}),
    jsonRoute({path: '/orgs/:owner/security/campaigns/:number', Component: OrgSecurityCampaignShow}),
    jsonRoute({path: '/orgs/:owner/security/campaigns/:number/publish', Component: OrgDraftSecurityCampaignPublish}),
    jsonRoute({path: '/orgs/:owner/security/campaigns/publish', Component: OrgSecurityCampaignPublish}),
    jsonRoute({path: '/orgs/:owner/security/campaigns/closed', Component: ClosedSecurityCampaigns}),
  ],
}))

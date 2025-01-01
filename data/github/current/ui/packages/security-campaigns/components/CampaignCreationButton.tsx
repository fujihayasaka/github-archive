import {ActionList, ActionMenu, Tooltip} from '@primer/react'
import {useNavigate} from '@github-ui/use-navigate'
import {securityCampaignsOrgNewCampaignPath} from '@github-ui/paths'

export interface CampaignCreationButtonProps {
  organizationLogin: string
  maxCampaignsReached: boolean
  maxOpenCampaigns: number
  maxDraftCampaigns: number
  hasSpam: boolean
  setIsTemplatesDialogOpen: (isOpen: boolean) => void
}

export const CampaignCreationButton = ({
  organizationLogin,
  maxCampaignsReached,
  maxOpenCampaigns,
  maxDraftCampaigns,
  hasSpam,
  setIsTemplatesDialogOpen,
}: CampaignCreationButtonProps) => {
  const navigate = useNavigate()

  const onCreateFromFilters = () => {
    navigate(securityCampaignsOrgNewCampaignPath({org: organizationLogin}))
  }
  const onCreateFromTemplate = () => {
    setIsTemplatesDialogOpen(true)
  }

  const tooltipText = `Limit of ${maxOpenCampaigns} open and ${maxDraftCampaigns} draft ${
    hasSpam ? 'and spam ' : ''
  }campaigns has been reached`

  const createButton = (
    <ActionMenu.Button variant="primary" inactive={maxCampaignsReached}>
      Create campaign
    </ActionMenu.Button>
  )

  if (maxCampaignsReached) {
    return <Tooltip text={tooltipText}>{createButton}</Tooltip>
  }

  return (
    <ActionMenu>
      {createButton}
      <ActionMenu.Overlay width="small">
        <ActionList>
          <ActionList.Item onSelect={onCreateFromTemplate} disabled={maxCampaignsReached}>
            From template
          </ActionList.Item>
          <ActionList.Item onSelect={onCreateFromFilters} disabled={maxCampaignsReached}>
            From code scanning filters
          </ActionList.Item>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}

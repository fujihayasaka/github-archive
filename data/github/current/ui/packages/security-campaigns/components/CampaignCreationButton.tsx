import {ActionList, ActionMenu, Button, Tooltip} from '@primer/react'
import {useNavigate} from '@github-ui/use-navigate'
import {securityCampaignsOrgNewCampaignPath} from '@github-ui/paths'

export interface CampaignCreationButtonProps {
  organizationLogin: string
  maxCampaignsReached: boolean
  maxOpenCampaigns: number
  maxDraftCampaigns: number
  setIsTemplatesDialogOpen: (isOpen: boolean) => void
  draftCampaignsEnabled: boolean
}

export const CampaignCreationButton = ({
  organizationLogin,
  maxCampaignsReached,
  maxOpenCampaigns,
  maxDraftCampaigns,
  setIsTemplatesDialogOpen,
  draftCampaignsEnabled,
}: CampaignCreationButtonProps) => {
  const navigate = useNavigate()

  const onCreateFromFilters = () => {
    if (draftCampaignsEnabled) {
      navigate(securityCampaignsOrgNewCampaignPath({org: organizationLogin}))
    } else {
      setIsTemplatesDialogOpen(true)
    }
  }
  const onCreateFromTemplate = () => {
    setIsTemplatesDialogOpen(true)
  }

  const tooltipText = `Limit of ${maxOpenCampaigns} open and ${maxDraftCampaigns} draft campaigns has been reached`

  const createButton = (
    <ActionMenu.Button variant="primary" inactive={maxCampaignsReached}>
      Create campaign
    </ActionMenu.Button>
  )

  return draftCampaignsEnabled ? (
    <ActionMenu>
      {maxCampaignsReached ? <Tooltip text={tooltipText}>{createButton}</Tooltip> : createButton}
      <ActionMenu.Overlay>
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
  ) : (
    <Button variant="primary" onClick={() => setIsTemplatesDialogOpen(true)}>
      Create campaign
    </Button>
  )
}

import {ActionList, Dialog} from '@primer/react'
import {useCallback} from 'react'
import type {SecurityCampaignTemplate} from '../types/security-campaign-template'
import {ArrowRightIcon} from '@primer/octicons-react'
import {securityCampaignsOrgNewCampaignPath} from '@github-ui/paths'

export type TemplateSelectionDialogProps = {
  setIsOpen: (value: boolean) => void
  templates: SecurityCampaignTemplate[]
  organizationLogin: string
}

export const TemplateSelectionDialog = ({setIsOpen, templates, organizationLogin}: TemplateSelectionDialogProps) => {
  const onDialogClose = useCallback(() => setIsOpen(false), [setIsOpen])

  return (
    <Dialog
      title="Select a template for your campaign"
      subtitle="Start a new security campaign to help teams remediate code scanning alerts with the help of Copilot Autofix."
      onClose={onDialogClose}
    >
      <ActionList>
        {templates.map(template => (
          <ActionList.LinkItem
            href={
              template.query
                ? securityCampaignsOrgNewCampaignPath({
                    org: organizationLogin,
                    query: template.query,
                    templateId: template.id,
                  })
                : template.href
            }
            key={template.id}
          >
            {template.name}
            <ActionList.Description variant="block">{template.description}</ActionList.Description>
            <ActionList.TrailingVisual>
              <ArrowRightIcon />
            </ActionList.TrailingVisual>
          </ActionList.LinkItem>
        ))}
      </ActionList>
    </Dialog>
  )
}

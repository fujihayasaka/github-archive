import {IconButtonWithTooltip} from '@github-ui/icon-button-with-tooltip'
import {useNavigate} from '@github-ui/use-navigate'
import {BeakerIcon, CommentIcon, KebabHorizontalIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu} from '@primer/react'
import {useState} from 'react'
import styles from '../DashboardLists.module.css'

export interface IssueActionListProps {
  onShowPromptDialog: () => void
}

export function IssueActionMenu({onShowPromptDialog}: IssueActionListProps) {
  const [open, setOpen] = useState(false)
  const navigate = useNavigate()

  return (
    <ActionMenu open={open} onOpenChange={() => setOpen(prev => !prev)}>
      <ActionMenu.Anchor>
        <IconButtonWithTooltip
          icon={KebabHorizontalIcon}
          variant="invisible"
          label="Summary options"
          tooltipDirection="s"
          hideTooltip={open}
          className={styles.Muted}
        />
      </ActionMenu.Anchor>
      <ActionMenu.Overlay width="small" align="end">
        <ActionList>
          <ActionList.Item onSelect={() => onShowPromptDialog()}>
            <ActionList.LeadingVisual>
              <BeakerIcon />
            </ActionList.LeadingVisual>
            Adjust prompt
          </ActionList.Item>
          <ActionList.Item onSelect={() => navigate('/github/dashboard/discussions/42')}>
            Give feedback
            <ActionList.LeadingVisual>
              <CommentIcon />
            </ActionList.LeadingVisual>
          </ActionList.Item>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}

import {forwardRef, useRef} from 'react'
import {ActionList, ActionMenu, IconButton, useRefObjectAsForwardedRef} from '@primer/react'
import {graphql, useFragment} from 'react-relay'
import type {IssueTypeItemMenuItem$key} from './__generated__/IssueTypeItemMenuItem.graphql'
import {Resources} from '../constants/strings'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
import {KebabHorizontalIcon} from '@primer/octicons-react'

type IssueTypeItemMenuProps = {
  issueType: IssueTypeItemMenuItem$key
  owner?: string
  toggleIssueType: () => void
  handleDelete: () => void
}

export const IssueTypeItemMenu = forwardRef<HTMLElement, IssueTypeItemMenuProps>(
  ({issueType, owner, toggleIssueType, handleDelete}, forwardedRef) => {
    const data = useFragment<IssueTypeItemMenuItem$key>(
      graphql`
        fragment IssueTypeItemMenuItem on IssueType {
          id
          isEnabled
          name
        }
      `,
      issueType,
    )

    const handleSelect = () => {
      if (ssrSafeWindow) ssrSafeWindow.location.href = `/organizations/${owner}/settings/issue-types/${data.id}`
    }

    const ref = useRef<HTMLElement | null>(null)
    useRefObjectAsForwardedRef(forwardedRef, ref)

    return (
      <ActionMenu anchorRef={ref}>
        <ActionMenu.Anchor>
          <IconButton
            data-testid="overflow-menu-anchor"
            aria-label={`Open type options for ${data.name}`}
            variant="invisible"
            icon={KebabHorizontalIcon}
          />
        </ActionMenu.Anchor>
        <ActionMenu.Overlay>
          <ActionList>
            <ActionList.Item onSelect={handleSelect}>{Resources.editButton}</ActionList.Item>
            <ActionList.Item data-testid={`menu-enable-option-${data.id}`} onSelect={toggleIssueType}>
              {data.isEnabled ? Resources.disableButton : Resources.enableButton}
            </ActionList.Item>
            <ActionList.Divider />
            <ActionList.Item data-testid={`menu-delete-option-${data.id}`} onSelect={handleDelete} variant="danger">
              {Resources.deleteButton}
            </ActionList.Item>
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    )
  },
)

IssueTypeItemMenu.displayName = 'IssueTypeItemMenu'

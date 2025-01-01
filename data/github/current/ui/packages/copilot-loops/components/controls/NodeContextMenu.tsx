import {KebabHorizontalIcon, TrashIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton} from '@primer/react'
import {useLoopOperations} from '../../hooks/use-loop-operations'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'

export function NodeContextMenu({nodeId}: {nodeId: string}) {
  const featureFlags = useFeatureFlags()
  const {removeNode} = useLoopOperations()

  const handleDeleteNode = () => {
    removeNode(nodeId)
  }

  if (!featureFlags['copilot_loops_post_staff_ship_features']) return null

  return (
    <ActionMenu>
      <ActionMenu.Anchor>
        <IconButton aria-label="Additional actions" icon={KebabHorizontalIcon} />
      </ActionMenu.Anchor>
      <ActionMenu.Overlay align="end">
        <ActionList>
          <ActionList.Item onSelect={handleDeleteNode} variant="danger">
            <ActionList.LeadingVisual>
              <TrashIcon />
            </ActionList.LeadingVisual>
            Delete
          </ActionList.Item>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}

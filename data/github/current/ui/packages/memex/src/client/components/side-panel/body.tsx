import {Box, Spinner} from '@primer/react'
import {useMemo} from 'react'

import {ItemType} from '../../api/memex-items/item-type'
import type {ReactionEmotion} from '../../api/side-panel/contracts'
import {DraftEdit} from '../../api/stats/contracts'
import {usePostStats} from '../../hooks/common/use-post-stats'
import type {MemexItemModel} from '../../models/memex-item-model'
import {useIssueContext} from '../../state-providers/issues/use-issue-context'
import {SidePanelComment} from './comment'
import {SidePanelLiveUpdate} from './live-update'

export const SidePanelBody: React.FC<{item: MemexItemModel; isLoading: boolean; fullHeight?: boolean}> = ({
  item,
  isLoading,
  fullHeight,
}) => {
  const {sidePanelMetadata, editIssue, reactToSidePanelItem} = useIssueContext()

  const {postStats} = usePostStats()

  const capabilities = useMemo(() => new Set(sidePanelMetadata.capabilities), [sidePanelMetadata])

  const onReact = capabilities.has('react')
    ? (reaction: ReactionEmotion, reacted: boolean, actor: string) => reactToSidePanelItem(reaction, reacted, actor)
    : undefined

  const onEdit = useMemo(
    () =>
      capabilities.has('editDescription')
        ? async (body: string) => {
            await editIssue({body})
            if (item.contentType === ItemType.DraftIssue)
              postStats({
                name: DraftEdit,
                memexProjectItemId: item.id,
              })
          }
        : undefined,
    [capabilities, editIssue, item.contentType, postStats, item.id],
  )

  return (
    <Box sx={{flex: fullHeight ? 'auto' : undefined, px: 2}}>
      <SidePanelLiveUpdate />
      {isLoading ? (
        <Box
          sx={{
            display: 'flex',
            flexDirection: 'row',
            py: 6,
            justifyContent: 'center',
          }}
        >
          <Spinner aria-label="Loading" />
        </Box>
      ) : (
        <Box as="section" sx={{height: fullHeight ? '100%' : undefined}}>
          <h3 style={{position: 'absolute', clipPath: 'circle(0)'}}>Description</h3>
          <SidePanelComment
            key={item.itemId()}
            allowEmptyBody
            author={sidePanelMetadata.user}
            createdAt={new Date(sidePanelMetadata.createdAt)}
            editedAt={
              sidePanelMetadata.description.editedAt ? new Date(sidePanelMetadata.description.editedAt) : undefined
            }
            reactions={sidePanelMetadata.reactions ?? {}}
            description={sidePanelMetadata.description}
            onEdit={onEdit}
            onReact={onReact}
          />
        </Box>
      )}
    </Box>
  )
}

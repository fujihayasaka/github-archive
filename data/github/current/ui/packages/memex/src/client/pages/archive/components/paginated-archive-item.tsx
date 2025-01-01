import {HistoryIcon, KebabHorizontalIcon, TrashIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Checkbox, IconButton, RelativeTime} from '@primer/react'
import {memo, useCallback, useMemo} from 'react'

import type {ColumnData} from '../../../api/columns/contracts/storage'
import type {RemoveMemexItemRequest, UnarchiveMemexItemRequest} from '../../../api/memex-items/contracts'
import {ItemType} from '../../../api/memex-items/item-type'
import {MemexItemIcon} from '../../../components/common/memex-item-icon'
import {InteractiveItemTitle} from '../../../components/interactive-item-title'
import {isNumber, parseTitleNumber} from '../../../helpers/parsing'
import {ViewerPrivileges} from '../../../helpers/viewer-privileges'
import {EmptyValue, withValue} from '../../../models/column-value'
import type {MemexItemModel} from '../../../models/memex-item-model'
import styles from './paginated-archive-item.module.css'

type PaginatedArchiveItemProps = {
  archivedItem: MemexItemModel
  columnData: ColumnData
  canRestore: boolean
  projectItemLimit: number
  isSelected: boolean
  onToggleSelection: () => void
  onRestoreItems: (request: UnarchiveMemexItemRequest) => void
  onRemoveItems: (request: RemoveMemexItemRequest) => void
  mutationLoading: boolean
}

export const PaginatedArchiveItem = memo<PaginatedArchiveItemProps>(function PaginatedArchiveItem({
  archivedItem,
  columnData,
  canRestore,
  projectItemLimit,
  isSelected,
  onToggleSelection,
  onRestoreItems,
  onRemoveItems,
  mutationLoading,
}) {
  const {hasWritePermissions} = ViewerPrivileges()
  const archivedAt = archivedItem.archived?.archivedAt
  const wasRecentlyRestored = !archivedAt
  const isRedactedItem = archivedItem.contentType === ItemType.RedactedItem
  const isReadonly = isRedactedItem || wasRecentlyRestored || !hasWritePermissions

  const itemTitleId = `item-title-${archivedItem.id}`

  const titleValue = columnData.Title
  const titleColumnValue = titleValue ? withValue(titleValue) : EmptyValue
  const number = parseTitleNumber(titleValue)

  // For archived items, this is the true time at which the item was most recently archived.
  //
  // For items that are not archived (i.e. recently restored), this is a fake timestamp that we display as part of an
  // optimistic update. Ultimately, we expect a live update to remove these items entirely, but we display this as a
  // "restored at" timestamp in the meantime. It is set to 1 second before the archived at timestamp was cleared (so
  // that it appears in the UI as having been *just* restored), and we intentionally do not update that time on
  // subsequent renders so that it appears stable to end users.
  const lastModifiedAt = useMemo(() => archivedAt || new Date(Date.now() - 1000).toISOString(), [archivedAt])

  const onRestore = useCallback(() => {
    onRestoreItems({memexProjectItemIds: [archivedItem.id]})
  }, [onRestoreItems, archivedItem.id])
  const onRemove = useCallback(() => {
    onRemoveItems({memexProjectItemIds: [archivedItem.id]})
  }, [onRemoveItems, archivedItem.id])

  return (
    <>
      <label className={styles.Box}>
        <Checkbox
          aria-labelledby={itemTitleId}
          checked={isReadonly ? false : isSelected}
          onChange={isReadonly ? undefined : onToggleSelection}
          disabled={isReadonly || mutationLoading}
          className={styles.Checkbox}
        />
      </label>
      <div className={styles.Box_1}>
        <MemexItemIcon titleColumn={titleColumnValue} isBlocked={archivedItem.isBlocked()} />
      </div>
      <div className={styles.Box_2}>
        <div id={itemTitleId} className={styles.Box_3}>
          <InteractiveItemTitle model={archivedItem} currentValue={titleColumnValue} />
          {isNumber(number) && (
            <div className={styles.Box_4}>
              <span className={styles.Text}> #{number}</span>
            </div>
          )}
        </div>

        <div className={styles.Box_5}>
          {archivedItem.archived ? 'archived' : 'restored'} <RelativeTime datetime={lastModifiedAt} />
          {!isRedactedItem && archivedItem.archived?.archivedBy ? (
            <>
              {' by '}
              <span className={styles.Text_1}>{archivedItem.archived.archivedBy.login}</span>
            </>
          ) : null}
        </div>
      </div>
      <div className={styles.Box_6}>
        {isReadonly || mutationLoading ? null : (
          <ActionMenu>
            <ActionMenu.Anchor>
              <IconButton
                icon={KebabHorizontalIcon}
                variant="invisible"
                aria-label="Open item actions"
                className={styles.Text_1}
              />
            </ActionMenu.Anchor>
            <ActionMenu.Overlay>
              <ActionList>
                <ActionList.Item onSelect={onRestore} disabled={!canRestore}>
                  <ActionList.LeadingVisual>
                    <HistoryIcon />
                  </ActionList.LeadingVisual>
                  {canRestore ? (
                    'Restore'
                  ) : (
                    <>
                      Restore unavailable
                      <ActionList.Description variant="block">
                        This will exceed the {projectItemLimit} project item limit
                      </ActionList.Description>
                    </>
                  )}
                </ActionList.Item>
                <ActionList.Item onSelect={onRemove} variant="danger">
                  <ActionList.LeadingVisual>
                    <TrashIcon />
                  </ActionList.LeadingVisual>
                  Delete from project
                </ActionList.Item>
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        )}
      </div>
    </>
  )
})

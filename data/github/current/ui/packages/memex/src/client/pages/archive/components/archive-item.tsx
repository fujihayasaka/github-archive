import {HistoryIcon, KebabHorizontalIcon, TrashIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Checkbox, IconButton, RelativeTime} from '@primer/react'
import {memo, useCallback} from 'react'

import type {ColumnData} from '../../../api/columns/contracts/storage'
import {ItemType} from '../../../api/memex-items/item-type'
import {ArchivePageRowActionMenu} from '../../../api/stats/contracts'
import {MemexItemIcon} from '../../../components/common/memex-item-icon'
import {InteractiveItemTitle} from '../../../components/interactive-item-title'
import {isNumber, parseTitleNumber} from '../../../helpers/parsing'
import {ViewerPrivileges} from '../../../helpers/viewer-privileges'
import {EmptyValue, withValue} from '../../../models/column-value'
import type {MemexItemModel} from '../../../models/memex-item-model'
import {useArchiveStatus} from '../../../state-providers/workflows/use-archive-status'
import {useRemoveArchiveItems, useRestoreArchiveItems, useSelectArchiveItems} from '../archive-page-provider'
import styles from './archive-item.module.css'

type ArchiveItemProps = {
  archivedItem: MemexItemModel
  columnData: ColumnData
  canRestore: boolean
  projectItemLimit: number
}

export const ArchiveItem = memo<ArchiveItemProps>(function ArchiveItem({
  archivedItem,
  columnData,
  canRestore,
  projectItemLimit,
}) {
  const {hasWritePermissions} = ViewerPrivileges()
  const {restoreItemsRequest} = useRestoreArchiveItems()
  const {setArchiveStatus} = useArchiveStatus()
  const restore = useCallback(async () => {
    const items = [archivedItem]
    await restoreItemsRequest.perform(items, items)
    setArchiveStatus()
  }, [archivedItem, restoreItemsRequest, setArchiveStatus])

  const {selectItem, isSelected} = useSelectArchiveItems()

  const onCheck = useCallback(() => {
    selectItem(archivedItem.id)
  }, [archivedItem, selectItem])

  const {removeItems} = useRemoveArchiveItems()
  const remove = useCallback(() => {
    removeItems([archivedItem.id], ArchivePageRowActionMenu)
  }, [archivedItem.id, removeItems])

  const itemTitleId = `item-title-${archivedItem.id}`

  const titleValue = columnData.Title
  const titleColumnValue = titleValue ? withValue(titleValue) : EmptyValue
  const number = parseTitleNumber(titleValue)

  const isRedactedItem = archivedItem.contentType === ItemType.RedactedItem
  const isRedactedOrReadOnly = isRedactedItem || !hasWritePermissions

  return (
    <>
      <label className={styles.Box}>
        <Checkbox
          aria-labelledby={itemTitleId}
          checked={isRedactedOrReadOnly ? false : isSelected(archivedItem.id)}
          onChange={isRedactedOrReadOnly ? undefined : onCheck}
          disabled={isRedactedOrReadOnly}
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
          {/* Data should be strongly consistent in this component, so ignore the fact that archived might be null */}
          archived <RelativeTime datetime={archivedItem.archived?.archivedAt} />
          {!isRedactedItem && archivedItem.archived?.archivedBy ? (
            <>
              {' by '}
              <span className={styles.Text_1}>{archivedItem.archived.archivedBy.login}</span>
            </>
          ) : null}
        </div>
      </div>
      <div className={styles.Box_6}>
        {isRedactedOrReadOnly ? null : (
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
                <ActionList.Item onSelect={restore} disabled={!canRestore}>
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
                <ActionList.Item onSelect={remove} variant="danger">
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

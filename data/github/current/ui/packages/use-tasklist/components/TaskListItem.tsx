import {DragAndDrop} from '@github-ui/drag-and-drop'
import {UnsafeHTMLDiv} from '@github-ui/safe-html/UnsafeHTML'
import type {OnConvertToIssueCallback, OnConvertToSubIssueCallback} from '@github-ui/markdown-viewer/types'
import {Box, Checkbox, Spinner} from '@primer/react'
import {useCallback, useEffect, useMemo, useState} from 'react'
import type {TaskItem} from '../constants/types'
import {handleItemToggle} from '../utils/handle-item-toggle'
import styles from './TaskListItem.module.css'
import {TaskListMenu} from './TaskListMenu'

export type TaskListItemProps = {
  markdownValue: string
  onChange: (markdown: string) => void | Promise<void>
  onConvertToIssue?: OnConvertToIssueCallback
  onConvertToSubIssue?: OnConvertToSubIssueCallback
  nested?: boolean
  position?: number
  item: TaskItem
  totalItems: number
  disabled?: boolean
  hideActions?: boolean
  itemIdToFocus?: string | number | null
  setitemIdToFocus?: React.Dispatch<React.SetStateAction<string | number | null>>
}

const ISSUES_REGEX = /\/issues\/\d*\d/

// Check if there are references mixed in with any other content by rendering the content, removing the references
// and checking if there is any left over content
const isConvertable = (content: string, isIssueConversion: boolean) => {
  const renderedContent = document.createElement('div')
  renderedContent.innerHTML = content
  const references = renderedContent.querySelectorAll('span.reference')
  // If there are 0 references, then it is just some form of text, so it is convertable
  if (references.length === 0) {
    return true
  }
  // If we are testing if this content is convertable to an issue, we return false if there are any references at all
  if (isIssueConversion) {
    return false
  }
  // If there is more than 1 reference, we can't know which reference to use in conversion, so it is not convertable
  if (references.length > 1) {
    return false
  }
  const onlyReference = references[0] as HTMLElement

  // If there is content left over after removing the reference, then it is mixed content and not convertable
  onlyReference.remove()
  if (renderedContent.innerHTML.trim() !== '') {
    return false
  }
  // We can only convert issues to sub-issues, so if the reference is not an issue, then it is not convertable
  if (!ISSUES_REGEX.test(onlyReference.innerHTML)) {
    return false
  }
  return true
}

export function TaskListItem({
  markdownValue,
  onChange,
  onConvertToIssue,
  onConvertToSubIssue,
  nested = false,
  position = 1,
  item,
  totalItems,
  disabled,
  hideActions,
  itemIdToFocus,
  setitemIdToFocus,
}: TaskListItemProps) {
  const [checked, setChecked] = useState(item.checked)
  const [showTrigger, setShowTrigger] = useState(false)
  const [isConverting, setIsConverting] = useState(false)

  const handleOnDropFocus = (itemId: string | number) => {
    const newlyDroppedItem = document.getElementById(`task-list-menu-item-${itemId}`)
    if (newlyDroppedItem) {
      newlyDroppedItem.focus()
    }
  }

  useEffect(() => {
    if (itemIdToFocus && !disabled) {
      handleOnDropFocus(itemIdToFocus)
      setitemIdToFocus?.(null)
    }
  }, [itemIdToFocus, disabled, setitemIdToFocus])

  const onToggleItem = useCallback(
    (markdown: string) => {
      setChecked(!item.checked)

      handleItemToggle({markdownValue: markdown, markdownIndex: item.markdownIndex, onChange})
    },
    [item, onChange],
  )

  const allowReordering =
    (!nested && !item.hasDifferentListTypes) ||
    (nested && position < 2 && !item.parentIsChecklist && !item.hasDifferentListTypes)

  const [canConvertToIssue, canConvertToSubIssue] = useMemo(
    () => [isConvertable(item.content, true), isConvertable(item.content, false)],
    [item.content],
  )

  const tasklistIstemTestIdBase = `tasklist-item-${position}-${item.markdownIndex}`

  let tasklistItemCssClasses =
    nested && (!onConvertToIssue || !onConvertToSubIssue)
      ? styles['no-convert-task-list-item']
      : styles['task-list-item']

  tasklistItemCssClasses += ` ${nested && totalItems > 0 ? 'contains-task-list' : ''}`
  tasklistItemCssClasses += disabled ? ` ${styles.disabled}` : ''

  return (
    <div
      className={tasklistItemCssClasses}
      onMouseEnter={() => setShowTrigger(true)}
      onMouseLeave={() => setShowTrigger(false)}
      data-testid={tasklistIstemTestIdBase}
    >
      <div className={styles['left-aligned-content']}>
        <div className={styles['drag-drop-container']}>
          {allowReordering && !disabled && (
            <DragAndDrop.DragTrigger
              className={`${styles['drag-handle-icon']} ${showTrigger ? styles['show-trigger'] : ''}`}
              style={{
                width: '20px',
                height: '28px',
              }}
            />
          )}
        </div>

        <div className={styles['checkbox-items']} id={`checkbox-item-${item.id}`}>
          <Checkbox
            checked={checked}
            disabled={disabled}
            onChange={e => {
              e.preventDefault()
              e.stopPropagation()
              onToggleItem(markdownValue)
            }}
            aria-label={`${item.title} checklist item`}
            className={styles.Checkbox}
          />
          <UnsafeHTMLDiv html={item.content} className={styles['task-list-html']} />
        </div>
      </div>
      <Box
        sx={{
          display: 'flex',
          justifyContent: 'center',
          alignItems: 'center',
          flexShrink: 0,
          flexBasis: '28px',
          height: '28px',
        }}
      >
        {isConverting && <Spinner size="small" />}

        {!hideActions && allowReordering && item.position && !isConverting && (
          <TaskListMenu
            data-testid={`${tasklistIstemTestIdBase}-menu`}
            onConvertToIssue={onConvertToIssue}
            onConvertToSubIssue={onConvertToSubIssue}
            totalItems={totalItems}
            item={item}
            disabled={disabled}
            allowIssueConversion={canConvertToIssue}
            allowSubIssueConversion={canConvertToSubIssue}
            setIsConverting={setIsConverting}
            allowReordering={allowReordering}
          />
        )}
      </Box>
    </div>
  )
}

import {testIdProps} from '@github-ui/test-id-props'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {ArchiveIcon, CheckIcon, CopyIcon, IssueOpenedIcon, LinkExternalIcon, TrashIcon} from '@primer/octicons-react'
import {ActionList, Text, useConfirm} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {forwardRef, useMemo, useRef, useState} from 'react'

import {SidePanelTypeParam} from '../../../api/memex-items/side-panel-item'
import {DraftConvert, SidePanelNavigateToItem, SidePanelUI} from '../../../api/stats/contracts'
import {ViewerPrivileges} from '../../../helpers/viewer-privileges'
import {useTimeout} from '../../../hooks/common/timeouts/use-timeout'
import {usePostStats} from '../../../hooks/common/use-post-stats'
import {useArchiveMemexItemsWithConfirmation} from '../../../hooks/use-archive-memex-items-with-confirmation'
import {useRemoveMemexItemWithConfirmation} from '../../../hooks/use-remove-memex-items-with-id'
import {useSidePanel} from '../../../hooks/use-side-panel'
import {DraftIssueModel, type MemexItemModel} from '../../../models/memex-item-model'
import {ITEM_ID_PARAM, PANE_PARAM} from '../../../platform/url'
import {useSearchParams} from '../../../router'
import {useMemexItems} from '../../../state-providers/memex-items/use-memex-items'
import {Resources} from '../../../strings'
import {RepoPicker} from '../../repo-picker'

export const SidePanelSidebarActions: React.FC<{item: MemexItemModel}> = ({item}) => {
  const {closePane, hasUnsavedChanges} = useSidePanel()
  const {postStats} = usePostStats()
  const {items: allItems} = useMemexItems()
  const [_, setSearchParams] = useSearchParams()

  const {hasWritePermissions} = ViewerPrivileges()
  const url = item.getUrl()

  const confirm = useConfirm()

  const confirmUnsavedChanges = async () =>
    !hasUnsavedChanges || (await confirm({...Resources.sidePanelCloseConfirmation, confirmButtonType: 'danger'}))

  // ---- convert

  const [repoPickerOpen, setRepoPickerOpen] = useState(false)
  const convertToIssueRef = useRef<HTMLLIElement>(null)

  const onConvertToIssue = () => {
    if (!confirmUnsavedChanges()) return
    setRepoPickerOpen(true)
  }

  const onPickConvertRepo = () => {
    postStats({
      name: DraftConvert,
      ui: SidePanelUI,
      memexProjectItemId: item.id,
    })
  }

  // ---- add to project

  const itemInProject = useMemo(
    () => allItems.find(i => i.itemId() === item.itemId() && i.contentType === item.contentType),
    [allItems, item],
  )
  const itemExistsInProject = !!itemInProject
  const shouldScroll = useRef(false)

  // Scroll issue into view when added
  useLayoutEffect(() => {
    const memexItemRef =
      document.querySelector(`[data-hovercard-subject-tag="issue:${item.itemId()}"]`) ||
      document.querySelector(`[data-board-card-id="${item.itemId()}"]`)
    if (shouldScroll.current && memexItemRef) {
      shouldScroll.current = false
      if ('scrollIntoViewIfNeeded' in memexItemRef && typeof memexItemRef.scrollIntoViewIfNeeded === 'function') {
        // This is part of webkit only, but not part of the official standard.
        // eslint-disable-next-line @typescript-eslint/no-unsafe-call
        memexItemRef.scrollIntoViewIfNeeded(false)
      } else {
        memexItemRef.scrollIntoView({block: 'nearest', behavior: 'smooth'})
      }
      // Update window URL for Copy link to Project once item is added
      if (itemInProject)
        setSearchParams(nextParams => {
          nextParams.set(PANE_PARAM, SidePanelTypeParam.ISSUE)
          nextParams.set(ITEM_ID_PARAM, itemInProject.id.toString())
          return nextParams
        })
    }
  })

  // ---- archive

  const {openArchiveConfirmationDialog} = useArchiveMemexItemsWithConfirmation(undefined, undefined, undefined, () =>
    closePane({force: true}),
  )

  const onArchive = () => {
    if (!confirmUnsavedChanges()) return
    if (itemExistsInProject) openArchiveConfirmationDialog([itemInProject.id], SidePanelUI)
  }

  // ---- delete

  const {openRemoveConfirmationDialog} = useRemoveMemexItemWithConfirmation(undefined, undefined, undefined, () =>
    closePane({force: true}),
  )

  const onDelete = () => {
    if (itemExistsInProject) openRemoveConfirmationDialog([itemInProject.id], SidePanelUI)
  }

  // ---- render

  const actions: Array<React.ReactNode> = []

  const canConvertToIssue = item instanceof DraftIssueModel && hasWritePermissions
  if (canConvertToIssue) {
    actions.push(<ConvertToIssueAction key="convert" onConvert={onConvertToIssue} ref={convertToIssueRef} />)
  }

  if (url)
    actions.push(
      <OpenInNewTabAction key="open" itemUrl={url} onClick={() => postStats({name: SidePanelNavigateToItem})} />,
      <CopyUrlAction key="copy" itemUrl={url} />,
    )

  if (itemExistsInProject) {
    actions.push(<CopyInProjectUrlAction key="copyInProjectLink" inProjectUrl={window.location.href} />)

    if (hasWritePermissions) {
      actions.push(
        <ArchiveAction key="archive" onArchive={onArchive} />,
        <DeleteAction key="delete" onDelete={onDelete} />,
      )
    }
  }

  return actions.length > 0 ? (
    <>
      <ActionList aria-label="Actions">
        <ActionList.Divider />
        {actions}
      </ActionList>
      {canConvertToIssue ? (
        <RepoPicker
          key="repoPicker"
          anchorRef={convertToIssueRef}
          isOpen={repoPickerOpen}
          item={item}
          onOpenChange={setRepoPickerOpen}
          onSuccess={onPickConvertRepo}
        />
      ) : null}
    </>
  ) : null
}

const ConvertToIssueAction = forwardRef<HTMLLIElement, {onConvert: () => void}>(({onConvert}, ref) => (
  <ActionList.Item onSelect={onConvert} ref={ref} {...testIdProps('side-pane-convert-to-issue')}>
    <ActionList.LeadingVisual>
      <IssueOpenedIcon />
    </ActionList.LeadingVisual>
    Convert to issue
  </ActionList.Item>
))
ConvertToIssueAction.displayName = 'ConvertToIssueAction'

const OpenInNewTabAction: React.FC<{itemUrl: string; onClick: () => void}> = ({itemUrl, onClick}) => (
  <ActionList.LinkItem target="_blank" href={itemUrl} onClick={onClick}>
    <ActionList.LeadingVisual>
      <LinkExternalIcon />
    </ActionList.LeadingVisual>
    Open in new tab
  </ActionList.LinkItem>
)

const CopyUrlAction: React.FC<{itemUrl: string}> = ({itemUrl}) => {
  const [success, setSuccess] = useState(false)
  const clearSuccessAfterTimeout = useTimeout(() => setSuccess(false), 2000)

  const onSelect = () => {
    navigator.clipboard.writeText(itemUrl)
    setSuccess(true)
    clearSuccessAfterTimeout()
  }

  return (
    <ActionList.Item onSelect={onSelect} {...testIdProps('copy-link-action')}>
      <ActionList.LeadingVisual>
        {success ? <Octicon icon={CheckIcon} sx={{color: 'success.fg'}} /> : <CopyIcon />}
      </ActionList.LeadingVisual>
      {success ? <Text sx={{fontWeight: 'bold', color: 'success.fg'}}>Copied!</Text> : 'Copy link'}
    </ActionList.Item>
  )
}

const CopyInProjectUrlAction: React.FC<{inProjectUrl: string}> = ({inProjectUrl}) => {
  const [success, setSuccess] = useState(false)
  const clearSuccessAfterTimeout = useTimeout(() => setSuccess(false), 2000)

  const onSelect = () => {
    navigator.clipboard.writeText(inProjectUrl)
    setSuccess(true)
    clearSuccessAfterTimeout()
  }

  return (
    <ActionList.Item onSelect={onSelect} {...testIdProps('copy-in-project-link-action')}>
      <ActionList.LeadingVisual>
        {success ? <Octicon icon={CheckIcon} sx={{color: 'success.fg'}} /> : <CopyIcon />}
      </ActionList.LeadingVisual>
      {success ? <Text sx={{fontWeight: 'bold', color: 'success.fg'}}>Copied!</Text> : 'Copy link in project'}
    </ActionList.Item>
  )
}

const ArchiveAction: React.FC<{onArchive: () => void}> = ({onArchive}) => (
  <ActionList.Item onSelect={onArchive}>
    <ActionList.LeadingVisual>
      <ArchiveIcon />
    </ActionList.LeadingVisual>
    Archive
  </ActionList.Item>
)

const DeleteAction: React.FC<{onDelete: () => void}> = ({onDelete}) => (
  <ActionList.Item onSelect={onDelete} variant="danger" {...testIdProps('side-pane-delete-action')}>
    <ActionList.LeadingVisual>
      <TrashIcon />
    </ActionList.LeadingVisual>
    Delete from project
  </ActionList.Item>
)

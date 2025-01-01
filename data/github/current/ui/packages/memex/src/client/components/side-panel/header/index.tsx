import {testIdProps} from '@github-ui/test-id-props'
import {useIgnoreKeyboardActionsWhileComposing} from '@github-ui/use-ignore-keyboard-actions-while-composing'
import {PinIcon, PinSlashIcon, XIcon} from '@primer/octicons-react'
import {Box, Button, IconButton, Link, RelativeTime, TextInput} from '@primer/react'
import {UnderlineNav} from '@primer/react/deprecated'
import {memo, useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {ItemType} from '../../../api/memex-items/item-type'
import {ItemKeyType, type SidePanelMetadata} from '../../../api/side-panel/contracts'
import {ItemRenameName, SidePanelNavigateToItem, SidePanelUI} from '../../../api/stats/contracts'
import {replaceShortCodesWithEmojis} from '../../../helpers/emojis'
import {SHORTCUTS} from '../../../helpers/keyboard-shortcuts'
import {ViewerPrivileges} from '../../../helpers/viewer-privileges'
import {usePostStats} from '../../../hooks/common/use-post-stats'
import {useApiRequest} from '../../../hooks/use-api-request'
import {useSidePanel} from '../../../hooks/use-side-panel'
import {useSidePanelDirtyState} from '../../../hooks/use-side-panel-dirty-state'
import type {MemexItemModel} from '../../../models/memex-item-model'
import {useIssueContext} from '../../../state-providers/issues/use-issue-context'
import {Resources} from '../../../strings'
import {EmojiAutocomplete} from '../../common/emoji-autocomplete'
import {SanitizedHtml} from '../../dom/sanitized-html'
import {RepositoryIcon} from '../../fields/repository/repository-icon'
import useToasts, {ToastType} from '../../toasts/use-toasts'
import {ItemStateLabel} from '../label'
import styles from './index.module.css'

export type SidePanelTabName = 'details' | 'tracks'

export const SidePanelHeader: React.FC<{
  item: MemexItemModel
  isLoading: boolean
  selectedTab: SidePanelTabName
  onTabChange: (tab: SidePanelTabName) => void
  showTabs: boolean
}> = memo(function SidePanelHeader({item, isLoading, selectedTab, onTabChange, showTabs}) {
  const {sidePanelMetadata} = useIssueContext()
  const {title, createdAt, user, state, itemKey} = sidePanelMetadata
  const showRepositoryHeader = item.contentType === ItemType.Issue

  return (
    <header className={styles.Box}>
      <div className={styles.Box_1}>
        <div className={styles.Box_2}>
          <div className={styles.Box_3}>
            <div className={styles.Box_4}>
              <SidePanelToolbar showCloseButton />

              {showRepositoryHeader && (
                <div className={styles.Box_6}>
                  <RepositoryHeader item={item} />
                </div>
              )}
            </div>

            <SidePanelTitle item={item} title={title} isLoading={isLoading} />

            {!isLoading && createdAt && user.login ? (
              <div className={styles.Box_7}>
                <ItemStateLabel itemType={itemKey.kind} state={state} />
                <address className={styles.Text}>
                  <span className={styles.Text_1}>{user.login}</span>
                  <span className={styles.Text_2}>
                    {' opened '}
                    <RelativeTime datetime={createdAt} />
                  </span>
                </address>
              </div>
            ) : null}
          </div>
        </div>
      </div>
      {showTabs ? (
        <SidePanelItemTabs selectedTab={selectedTab} onTabChange={onTabChange} />
      ) : (
        // tabs have a built-in border; if we don't render them then we need to add a visual separator
        <div className={styles.Box_8} />
      )}
    </header>
  )
})

SidePanelHeader.displayName = 'SidePanelHeader'

interface SidePanelTitleProps {
  item: MemexItemModel
  title: SidePanelMetadata['title']
  isLoading: boolean
}

// This is a static header for use until tasklist_block is fully enabled for the breadcrumb header
const RepositoryHeader: React.FC<{
  item: MemexItemModel
}> = ({item}) => {
  const repository = item.getExtendedRepository()
  const repoName = repository?.name || item.getRepositoryName() || ''
  const repoIcon = repository?.url ? <RepositoryIcon repository={repository} /> : undefined

  return (
    <div className={styles.Box_9}>
      {repoIcon && <span className={styles.Text_3}>{repoIcon}</span>}
      <span>{`${repoName} #${item.getItemNumber()}`}</span>
    </div>
  )
}

interface ToolbarProps {
  children?: React.ReactNode
  showCloseButton: boolean
}

export const SidePanelToolbar = ({children, showCloseButton}: ToolbarProps) => {
  const {pinButtonRef, closePane, pinned, setPinned} = useSidePanel()

  return (
    <div role="group" aria-label={Resources.sidePanelToolbarLabel} className={styles.Box_10}>
      {showCloseButton && (
        <IconButton
          variant="invisible"
          aria-label="Close panel"
          icon={XIcon}
          onClick={() => closePane()}
          {...testIdProps('side-panel-button-close')}
        />
      )}
      <IconButton
        variant="invisible"
        aria-label={pinned ? Resources.sidePanelUnpinLabel : Resources.sidePanelPinLabel}
        icon={pinned ? PinSlashIcon : PinIcon}
        onClick={() => setPinned(!pinned)}
        ref={pinButtonRef}
        tooltipDirection="sw"
      />
      {children}
    </div>
  )
}

const SidePanelTitle = memo(function SidePanelTitle({item, title, isLoading}: SidePanelTitleProps) {
  const [isEditing, setIsEditing] = useSidePanelDirtyState()
  const [editingTitle, setEditingTitle] = useState<string>('')
  const inputRef = useRef<HTMLInputElement>(null)
  const {hasWritePermissions} = ViewerPrivileges()
  const {postStats} = usePostStats()
  const {addToast} = useToasts()
  const {
    editIssueTitle,
    sidePanelMetadata: {capabilities, itemKey, issueNumber, url},
  } = useIssueContext()

  const canEditTitle = useMemo(() => capabilities?.includes('editTitle'), [capabilities])

  const setEditingTitleFromItem = useCallback(() => {
    if (isEditing) return

    setEditingTitle(title.raw)
  }, [title, isEditing])

  // Update the title if we receive a _new_ item only
  useEffect(() => setEditingTitleFromItem(), [setEditingTitleFromItem])

  const titleChangeRequest = useCallback(
    async (newValue: string) => {
      const newTitle = replaceShortCodesWithEmojis(newValue)

      await editIssueTitle(newTitle)
      postStats({
        name: ItemRenameName,
        ui: SidePanelUI,
        memexProjectItemId: item.id,
      })
    },
    [editIssueTitle, item, postStats],
  )

  const handleTitleChangeRequest = useApiRequest({
    request: titleChangeRequest,
    rollback: setEditingTitleFromItem,
  })

  const stopEditingAndSave = useCallback(async () => {
    if (inputRef.current && inputRef.current instanceof HTMLInputElement) {
      const newValue = inputRef.current.value.trim()
      if (newValue === '') {
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({message: Resources.titleCannotBeBlank, type: ToastType.warning})
        return
      }
      await handleTitleChangeRequest.perform(newValue)
    }
    setIsEditing(false)
  }, [handleTitleChangeRequest, addToast, setIsEditing])

  const onChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      setEditingTitle(e.target.value)
    },
    [setEditingTitle],
  )

  const onKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLInputElement>) => {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      switch (e.key) {
        case SHORTCUTS.ENTER:
          stopEditingAndSave()
          e.preventDefault()
          break

        case SHORTCUTS.ESCAPE:
          setEditingTitleFromItem()
          setIsEditing(false)
          e.preventDefault()
          break
      }
    },
    [stopEditingAndSave, setEditingTitleFromItem, setIsEditing],
  )

  const inputCompositionProps = useIgnoreKeyboardActionsWhileComposing(onKeyDown)

  const onClick = useCallback((): void => {
    if (hasWritePermissions) {
      setEditingTitleFromItem()
      setIsEditing(true)
    }
  }, [hasWritePermissions, setEditingTitleFromItem, setIsEditing])

  useEffect(() => {
    if (isEditing) {
      // If we just started editing, focus the newly rendered input
      inputRef.current?.focus()
    } else {
      // If we just stopped editing, and we didn't focus
      // on something else, then focus on the title input
      // eslint-disable-next-line @eslint-react/web-api/no-leaked-timeout
      window.setTimeout(() => {
        if (document.activeElement === document.body) {
          inputRef.current?.focus()
        }
      })
    }
  }, [isEditing])

  return (
    <Box
      sx={{
        pt: isEditing ? 1 : 0,
        mb: isEditing ? 1 : 0,
      }}
      className={styles.Box_11}
    >
      <div className={styles.Box_5} {...testIdProps('side-panel-title')}>
        {isEditing ? (
          <EmojiAutocomplete fullWidth>
            <TextInput
              aria-label="Item title"
              ref={inputRef}
              value={editingTitle}
              onChange={onChange}
              {...inputCompositionProps}
              size="small"
              className={styles.TextInput}
              {...testIdProps('side-panel-title-input')}
            />
          </EmojiAutocomplete>
        ) : (
          <h2 className={styles.Text_4} {...testIdProps('side-panel-title-content')}>
            {isLoading ? (
              <span className={styles.Text_5}>Loading...</span>
            ) : itemKey.kind === ItemKeyType.ISSUE && !!issueNumber && !!url ? (
              <Link
                href={url}
                target="_blank"
                onClick={() => postStats({name: SidePanelNavigateToItem})}
                className={styles.Link}
              >
                <SanitizedHtml as="bdi">{title.html}</SanitizedHtml>
                <span className={styles.Text_6}>#{issueNumber}</span>
              </Link>
            ) : (
              <SanitizedHtml as="bdi">{title.html}</SanitizedHtml>
            )}
          </h2>
        )}
      </div>
      <Box sx={{mt: isEditing ? 0 : 1}}>
        {!isEditing && !isLoading && canEditTitle && (
          <Button
            size="small"
            onClick={onClick}
            variant="invisible"
            {...testIdProps('side-panel-title-edit-button')}
            className={styles.Link}
          >
            {Resources.editTitle}
          </Button>
        )}
        {isEditing && (
          <div className={styles.Box_12}>
            <Button
              size="small"
              variant="primary"
              onClick={stopEditingAndSave}
              {...testIdProps('side-panel-title-save-button')}
            >
              Save
            </Button>
            <Button
              size="small"
              onClick={() => {
                setEditingTitleFromItem()
                setIsEditing(false)
              }}
              {...testIdProps('side-panel-title-revert-button')}
            >
              Cancel
            </Button>
          </div>
        )}
      </Box>
    </Box>
  )
})

const SidePanelItemTabs: React.FC<{
  selectedTab: SidePanelTabName
  onTabChange: (tab: SidePanelTabName) => void
}> = ({selectedTab, onTabChange}) => (
  <UnderlineNav className={styles.UnderlineNav}>
    <UnderlineNav.Link
      onClick={() => onTabChange('details')}
      selected={selectedTab === 'details'}
      className={styles.UnderlineNav_Link}
    >
      Details
    </UnderlineNav.Link>
    <UnderlineNav.Link
      onClick={() => onTabChange('tracks')}
      selected={selectedTab === 'tracks'}
      className={styles.UnderlineNav_Link}
    >
      Tracks
    </UnderlineNav.Link>
  </UnderlineNav>
)

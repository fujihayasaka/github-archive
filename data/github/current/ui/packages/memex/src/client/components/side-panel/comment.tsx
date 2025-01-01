import {CommentBox, type CommentBoxHandle} from '@github-ui/comment-box/CommentBox'
import {CommentBoxButton} from '@github-ui/comment-box/CommentBoxButton'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {MarkdownViewer} from '@github-ui/markdown-viewer'
import {testIdProps} from '@github-ui/test-id-props'
import {useDebounce} from '@github-ui/use-debounce'
import useIsMounted from '@github-ui/use-is-mounted'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {KebabHorizontalIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Box, Button, IconButton, Label, Link, RelativeTime, Text} from '@primer/react'
import {isValid} from 'date-fns'
import {useCallback, useRef, useState} from 'react'
import {flushSync} from 'react-dom'

import type {User} from '../../api/common-contracts'
import {
  CommentAuthorAssociation,
  type IssueMetadataDescription,
  type ReactionEmotion,
  type Reactions,
} from '../../api/side-panel/contracts'
import {getCommentBoxConfig} from '../../helpers/get-comment-box-config'
import {sanitizeRenderedMarkdown} from '../../helpers/sanitize'
import {toTitleCase} from '../../helpers/util'
import {useApiRequest} from '../../hooks/use-api-request'
import {useEnabledFeatures} from '../../hooks/use-enabled-features'
import {useSidePanel} from '../../hooks/use-side-panel'
import {useSidePanelDirtyState} from '../../hooks/use-side-panel-dirty-state'
import {Resources} from '../../strings'
import styles from './comment.module.css'
import {SidePanelReactions} from './reactions'
import {useSidePanelMarkdownSubject} from './use-side-panel-markdown-subject'

const ActionsOverflowMenu: React.FC<{
  url: string
  onEdit?: () => void
}> = ({url, onEdit}) => (
  <ActionMenu>
    <ActionMenu.Anchor>
      <IconButton
        icon={KebabHorizontalIcon}
        variant="invisible"
        size="small"
        aria-label="Comment actions"
        sx={{color: 'fg.default'}}
        {...testIdProps('comment-overflow-menu-button')}
      />
    </ActionMenu.Anchor>

    <ActionMenu.Overlay align="end">
      <ActionList>
        <ActionList.Item onSelect={() => navigator.clipboard.writeText(url)}>Copy link</ActionList.Item>
        {onEdit && (
          <ActionList.Item onSelect={onEdit} {...testIdProps('overflow-menu-edit-button')}>
            Edit
          </ActionList.Item>
        )}
      </ActionList>
    </ActionMenu.Overlay>
  </ActionMenu>
)

const Actions: React.FC<{
  url?: string
  onEdit?: () => void
}> = ({url, onEdit}) =>
  url ? (
    <ActionsOverflowMenu url={url} onEdit={onEdit} />
  ) : onEdit ? (
    <Button
      size="small"
      variant="invisible"
      sx={{
        color: 'fg.default',
      }}
      onClick={onEdit}
      aria-label="Edit comment"
      {...testIdProps('edit-comment-button')}
    >
      Edit
    </Button>
  ) : null

const Timestamp: React.FC<{createdAt: Date; editedAt?: Date}> = ({createdAt, editedAt}) => {
  const latestDate = editedAt ?? createdAt
  if (!isValid(latestDate)) {
    return null
  }
  return (
    <Text sx={{color: 'fg.muted'}} {...testIdProps('edit-timestamp')}>
      <RelativeTime date={latestDate} />
      {latestDate === editedAt && ' (edited)'}
    </Text>
  )
}

const Header: React.FC<{
  author: User
  authorAssociation?: CommentAuthorAssociation
  createdAt: Date
  editedAt?: Date
  url?: string
  onStartEdit?: () => void
}> = ({author, createdAt, editedAt, authorAssociation, url, onStartEdit}) => (
  <Box sx={{display: 'flex', justifyContent: 'space-between', gap: 2}} as="header">
    <Box sx={{display: 'flex', flexWrap: 'wrap', gap: 2, alignItems: 'center'}}>
      {author.avatarUrl && (
        <GitHubAvatar
          loading="lazy"
          size={24}
          key={author.id}
          alt="" // alt text not needed since we have the username right next to it
          src={author.avatarUrl}
          {...testIdProps('author-avatar')}
          sx={{flexShrink: 0}}
        />
      )}

      <Text sx={{fontWeight: 600, fontStyle: 'normal'}} {...testIdProps('author-login')} as="address">
        {author.login}
      </Text>

      {url ? (
        <Link href={url} target="_blank" {...testIdProps('edit-timestamp-link')}>
          <Timestamp createdAt={createdAt} editedAt={editedAt} />
        </Link>
      ) : (
        <Timestamp createdAt={createdAt} editedAt={editedAt} />
      )}

      {authorAssociation && authorAssociation !== CommentAuthorAssociation.NONE && (
        <>
          <Text sx={{color: 'fg.muted'}}>&middot;</Text>
          <Label sx={{fontWeight: 600, alignSelf: 'center'}} {...testIdProps('author-association')}>
            {toTitleCase(authorAssociation)}
          </Label>
        </>
      )}
    </Box>

    <Actions url={url} onEdit={onStartEdit} />
  </Box>
)

const EditorButtons: React.FC<{
  onCancel: () => void
  onSave: () => void
  updateButtonDisabled: boolean
}> = ({onCancel, onSave, updateButtonDisabled}) => (
  <>
    <CommentBoxButton variant="invisible" sx={{color: 'fg.muted'}} onClick={onCancel} {...testIdProps('cancel-button')}>
      Cancel
    </CommentBoxButton>
    <CommentBoxButton
      variant="primary"
      onClick={onSave}
      {...testIdProps('save-button')}
      disabled={updateButtonDisabled}
    >
      Update comment
    </CommentBoxButton>
  </>
)

export const SidePanelComment: React.FC<{
  allowEmptyBody?: boolean
  author: User
  authorAssociation?: CommentAuthorAssociation
  createdAt: Date
  editedAt?: Date
  url?: string

  description: IssueMetadataDescription
  onEdit?: (body: string) => Promise<void>

  reactions: Reactions
  onReact?: (reaction: ReactionEmotion, reacted: boolean, actor: string) => Promise<void>
}> = ({
  allowEmptyBody,
  author,
  authorAssociation,
  createdAt,
  editedAt,
  url,
  description,
  onEdit,
  reactions,
  onReact,
}) => {
  const [, setDirty] = useSidePanelDirtyState()
  const [isEditing, setIsEditing] = useState(false)
  const [isSaving, setIsSaving] = useState(false)
  const [editedBody, setEditedBody] = useState<string>(description.body || '')
  const editorRef = useRef<CommentBoxHandle>(null)
  const commentBoxConfig = getCommentBoxConfig()
  const viewerRef = useRef<HTMLDivElement>(null)
  const viewPlaceholderRef = useRef<HTMLParagraphElement>(null)
  const isMounted = useIsMounted()
  const {sidePanelState} = useSidePanel()
  const {memex_disable_draft_issue_file_upload} = useEnabledFeatures()

  const editorSubject = useSidePanelMarkdownSubject()

  const draftFileUploadsDisabled =
    sidePanelState?.type === 'issue' && 'isDraft' in sidePanelState.item && sidePanelState.item.isDraft()
      ? memex_disable_draft_issue_file_upload
      : false

  // The issue body is allowed to be empty, but issue comments are not.
  const canSaveComment = allowEmptyBody || editedBody.trim() !== ''

  const [renderedHtml, setRenderedHtml] = useState(description.bodyHtml ?? '')
  const resetRenderedHtml = useCallback(() => {
    if (isEditing) return

    // Don't reset the HTML if the user made another optimistic update or is currently dragging.
    if (viewerRef.current?.querySelector('.is-dirty')) return

    // If the user is not editing, reset the rendered HTML to the HTML from the response.
    if (viewerRef.current?.contains(document.activeElement)) return

    setRenderedHtml(description.bodyHtml ?? '')
  }, [description.bodyHtml, isEditing])

  useLayoutEffect(() => {
    // Keep the edited body in sync with the description body while not editing.
    if (!isEditing) {
      setEditedBody(description.body || '')
    }
  }, [description.body, isEditing])

  useLayoutEffect(() => {
    resetRenderedHtml()
  }, [resetRenderedHtml])

  const onChangeBody = useCallback(
    (newBody: React.SetStateAction<string>): void => {
      setEditedBody(newBody)
      setDirty(true)
    },
    [setEditedBody, setDirty],
  )

  const {perform: saveBody} = useApiRequest({
    request: async (viewBody?: string) => {
      if (!onEdit) return

      if (!viewBody) setIsSaving(true)
      await onEdit(viewBody || editedBody)
      if (isMounted()) setIsSaving(false)
    },
    rollback: () => {
      setIsSaving(false)
      resetRenderedHtml()
    },
    showErrorToast: true,
  })

  const debouncedSave = useDebounce(saveBody, 1000)

  const onInteractWithBody = useCallback(
    (value: string) => {
      setEditedBody(value)
      // Debounce to avoid disabling after every single checkbox click
      debouncedSave(undefined)
    },
    [debouncedSave],
  )

  const onStartEdit = onEdit
    ? () => {
        // eslint-disable-next-line @eslint-react/dom/no-flush-sync
        flushSync(() => {
          setIsEditing(true)
        })

        editorRef.current?.focus()
      }
    : undefined

  const onCancelEdit = () => {
    setIsEditing(false)
    setEditedBody(description.body || '')
    setDirty(false)
  }

  const onSaveEdit = async () => {
    // The server will reject a request if the body is empty, so don't
    // allow the client to send such a request.
    // We disable the button in this case, but we also need to guard here,
    // for the scenario where this function is called as the primary action
    // of the markdown editor.
    if (canSaveComment) {
      await saveBody(undefined)
      if (isMounted()) {
        setIsEditing(false)
        setDirty(false)
      }
    }
  }

  return isEditing ? (
    <>
      <CommentBox
        label="Edit comment"
        showLabel={false}
        ref={editorRef}
        value={editedBody}
        onChange={onChangeBody}
        onPrimaryAction={onSaveEdit}
        fileUploadsEnabled={!draftFileUploadsDisabled}
        subject={editorSubject}
        userSettings={commentBoxConfig}
        actions={<EditorButtons onSave={onSaveEdit} onCancel={onCancelEdit} updateButtonDisabled={!canSaveComment} />}
        className={styles.CommentBox}
        {...testIdProps('markdown-editor')}
      />
      {draftFileUploadsDisabled && (
        <Text as="p" sx={{fontStyle: 'italic', fontSize: 0, color: 'fg.muted', px: 3}}>
          File uploads have been disabled for draft issues in this organization.
        </Text>
      )}
    </>
  ) : (
    <Box
      sx={{
        display: 'flex',
        flexDirection: 'column',
        p: 3,
        gap: 3,
      }}
      as="article"
    >
      <Header
        author={author}
        createdAt={createdAt}
        editedAt={editedAt}
        url={url}
        onStartEdit={onStartEdit}
        authorAssociation={authorAssociation}
      />

      {description.bodyHtml ? (
        <div {...testIdProps('comment-body')} ref={viewerRef}>
          <MarkdownViewer
            verifiedHTML={sanitizeRenderedMarkdown(renderedHtml, {skipImageSanitization: true})}
            onChange={onInteractWithBody}
            markdownValue={description.body || ''}
            disabled={isSaving || !onEdit}
          />
        </div>
      ) : (
        <Text
          className="js-comment"
          sx={{color: 'fg.muted', m: 0, fontStyle: 'italic'}}
          as="p"
          ref={viewPlaceholderRef}
          {...testIdProps('empty-body-placeholder')}
        >
          {Resources.noDescriptionProvided}
        </Text>
      )}

      <footer>
        <Box
          sx={{
            display: 'flex',
            alignItems: 'center',
          }}
        >
          <SidePanelReactions reactions={reactions} onReact={onReact} />
        </Box>
      </footer>
    </Box>
  )
}

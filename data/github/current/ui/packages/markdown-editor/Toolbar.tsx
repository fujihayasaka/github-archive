import {FocusKeys} from '@primer/behaviors'
import {
  BoldIcon,
  CodeIcon,
  CrossReferenceIcon,
  HeadingIcon,
  ItalicIcon,
  LinkIcon,
  ListOrderedIcon,
  ListUnorderedIcon,
  MentionIcon,
  QuoteIcon,
  TasklistIcon,
} from '@primer/octicons-react'
import type React from 'react'
import {memo, useContext, useRef} from 'react'

import {isMacOS} from '@github-ui/get-os'
import {useFocusZone} from '@primer/react'
import {MarkdownEditorContext} from './MarkdownEditorContext'
import {SavedRepliesButton} from './SavedReplies'
import {ToolbarButton} from './ToolbarButton'

import styles from './Toolbar.module.css'

const Divider = () => {
  return <div className={styles.divider} />
}

export const DefaultToolbarButtons = memo(() => {
  const {condensed, formattingToolsRef} = useContext(MarkdownEditorContext)

  const cmdOrCtrl = isMacOS() ? 'Cmd' : 'Ctrl'

  // Important: do not replace `() => ref.current?.format()` with `ref.current?.format` - it will refer to an outdated ref.current!
  return (
    <>
      <div>
        <ToolbarButton
          onClick={() => formattingToolsRef.current?.header()}
          icon={HeadingIcon}
          aria-label="Add header text"
        />
        <ToolbarButton
          onClick={() => formattingToolsRef.current?.bold()}
          icon={BoldIcon}
          aria-label={`Bold (${cmdOrCtrl} + B)`}
        />
        <ToolbarButton
          onClick={() => formattingToolsRef.current?.italic()}
          icon={ItalicIcon}
          aria-label={`Italic (${cmdOrCtrl} + I)`}
        />
      </div>
      <div>
        <Divider />
        <ToolbarButton
          onClick={() => formattingToolsRef.current?.quote()}
          icon={QuoteIcon}
          aria-label={`Insert a quote (${cmdOrCtrl} + Shift + .)`}
        />
        <ToolbarButton
          onClick={() => formattingToolsRef.current?.code()}
          icon={CodeIcon}
          aria-label={`Insert code (${cmdOrCtrl} + E)`}
        />
        <ToolbarButton
          onClick={() => formattingToolsRef.current?.link()}
          icon={LinkIcon}
          aria-label={`Add a link (${cmdOrCtrl} + K)`}
        />
      </div>
      <div>
        <Divider />
        <ToolbarButton
          onClick={() => formattingToolsRef.current?.unorderedList()}
          icon={ListUnorderedIcon}
          aria-label={`Add a bulleted list (${cmdOrCtrl} + 8)`}
        />
        <ToolbarButton
          onClick={() => formattingToolsRef.current?.orderedList()}
          icon={ListOrderedIcon}
          aria-label={`Add a numbered list (${cmdOrCtrl} + Shift + 7)`}
        />
        <ToolbarButton
          onClick={() => formattingToolsRef.current?.taskList()}
          icon={TasklistIcon}
          aria-label={`Add a task list (${cmdOrCtrl} + Shift + L)`}
        />
      </div>
      {!condensed && (
        <div>
          <Divider />
          <ToolbarButton
            onClick={() => formattingToolsRef.current?.mention()}
            icon={MentionIcon}
            aria-label="Mention a user or team (@)"
          />
          <ToolbarButton
            onClick={() => formattingToolsRef.current?.reference()}
            icon={CrossReferenceIcon}
            aria-label="Reference an issue, pull request, or discussion (#)"
          />
        </div>
      )}
      <SavedRepliesButton />
    </>
  )
})
DefaultToolbarButtons.displayName = 'MarkdownEditor.DefaultToolbarButtons'

export const CoreToolbar = ({children}: {children?: React.ReactNode}) => {
  const containerRef = useRef<HTMLDivElement>(null)

  useFocusZone({
    containerRef,
    focusInStrategy: 'closest',
    bindKeys: FocusKeys.ArrowHorizontal | FocusKeys.HomeAndEnd,
    focusOutBehavior: 'wrap',
  })

  return (
    <div ref={containerRef} aria-label="Formatting tools" role="toolbar" className={styles.toolbar}>
      {children}
    </div>
  )
}

export const Toolbar = ({children}: {children?: React.ReactNode}) => <CoreToolbar>{children}</CoreToolbar>
Toolbar.displayName = 'MarkdownEditor.Toolbar'

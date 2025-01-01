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
import {useFocusZone} from '@primer/react'
import type React from 'react'
import {memo, useContext, useRef} from 'react'

import {MarkdownEditorContext} from './MarkdownEditorContext'
import {SavedRepliesButton} from './SavedReplies'
import styles from './Toolbar.module.css'
import {ToolbarButton} from './ToolbarButton'

const Divider = () => {
  return <div className={styles.divider} />
}

export const DefaultToolbarButtons = memo(() => {
  const {condensed, formattingToolsRef} = useContext(MarkdownEditorContext)

  // Important: do not replace `() => ref.current?.format()` with `ref.current?.format` - it will refer to an outdated ref.current!
  return (
    <>
      <div>
        <ToolbarButton onClick={() => formattingToolsRef.current?.header()} icon={HeadingIcon} aria-label="Heading" />
        <ToolbarButton onClick={() => formattingToolsRef.current?.bold()} icon={BoldIcon} aria-label="Bold" />
        <ToolbarButton onClick={() => formattingToolsRef.current?.italic()} icon={ItalicIcon} aria-label="Italic" />
      </div>
      <div>
        <Divider />
        <ToolbarButton onClick={() => formattingToolsRef.current?.quote()} icon={QuoteIcon} aria-label="Quote" />
        <ToolbarButton onClick={() => formattingToolsRef.current?.code()} icon={CodeIcon} aria-label="Code" />
        <ToolbarButton onClick={() => formattingToolsRef.current?.link()} icon={LinkIcon} aria-label="Link" />
      </div>
      <div>
        <Divider />
        <ToolbarButton
          onClick={() => formattingToolsRef.current?.unorderedList()}
          icon={ListUnorderedIcon}
          aria-label="Unordered list"
        />
        <ToolbarButton
          onClick={() => formattingToolsRef.current?.orderedList()}
          icon={ListOrderedIcon}
          aria-label="Numbered list"
        />
        <ToolbarButton
          onClick={() => formattingToolsRef.current?.taskList()}
          icon={TasklistIcon}
          aria-label="Task list"
        />
      </div>
      {!condensed && (
        <div>
          <Divider />
          <ToolbarButton
            onClick={() => formattingToolsRef.current?.mention()}
            icon={MentionIcon}
            aria-label="Mention"
          />
          <ToolbarButton
            onClick={() => formattingToolsRef.current?.reference()}
            icon={CrossReferenceIcon}
            aria-label="Reference"
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

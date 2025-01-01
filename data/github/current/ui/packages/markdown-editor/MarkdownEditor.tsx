import {isFeatureEnabled} from '@github-ui/feature-flags'
import {MarkdownViewer} from '@github-ui/markdown-viewer'
import {noop} from '@github-ui/noop'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {useIgnoreKeyboardActionsWhileComposing} from '@github-ui/use-ignore-keyboard-actions-while-composing'
import {useSafeAsyncCallback} from '@github-ui/use-safe-async-callback'
import {useSyntheticChange} from '@github-ui/use-synthetic-change'
import {StopIcon} from '@primer/octicons-react'
import {Flash, useIsomorphicLayoutEffect, useResizeObserver} from '@primer/react'
import {useSlots} from '@primer/react/experimental'
import {clsx} from 'clsx'
import {
  forwardRef,
  isValidElement,
  useCallback,
  useEffect,
  useId,
  useImperativeHandle,
  useMemo,
  useRef,
  useState,
} from 'react'

import {Actions} from './Actions'
import {ErrorMessage} from './ErrorMessage'
import {CoreFooter, Footer} from './Footer'
import {FormattingTools} from './FormattingTools'
import {Label} from './Label'
import styles from './MarkdownEditor.module.css'
import {MarkdownEditorContext} from './MarkdownEditorContext'
import {MarkdownInput} from './MarkdownInput'
import {SavedRepliesContext, type SavedRepliesHandle, type SavedReply} from './SavedReplies'
import type {SuggestionOptions} from './suggestions'
import type {Emoji} from './suggestions/use-emoji-suggestions'
import type {Mentionable} from './suggestions/use-mention-suggestions'
import type {Reference} from './suggestions/use-reference-suggestions'
import {CoreToolbar, DefaultToolbarButtons, Toolbar} from './Toolbar'
import {type FileType, type FileUploadResult, useFileHandling} from './use-file-handling'
import {useIndenting} from './use-indenting'
import {useListEditing} from './use-list-editing'
import {isModifierKey} from './utils'
import {type MarkdownViewMode, ViewSwitch} from './ViewSwitch'

export type MarkdownEditorProps = {
  /** Current value of the editor as a multiline markdown string. */
  value: string
  /** Called when the value changes. */
  onChange: (newMarkdown: string) => void
  /** Called when the textarea gains focus. */
  onInputFocus?: () => void
  /**
   * Accepts Markdown and returns rendered HTML. To prevent XSS attacks,
   * the HTML should be sanitized and/or come from a trusted source.
   */
  onRenderPreview: (markdown: string) => Promise<SafeHTMLString>
  children: React.ReactNode
  /** Disable the editor and all related buttons. Users can still switch between preview & edit modes. */
  disabled?: boolean
  /** Placeholder text to show when the editor is empty. By default, no placeholder will be shown. */
  placeholder?: string
  /** Maximum number of characters the markdown can hold (includes formatting characters like `*`). */
  maxLength?: number
  /**
   * Force the editor to take up the full height of the container and disallow resizing. Only
   * use when the container height is tall enough that the user will never want to expand the
   * input further, ie when it takes the full height of the viewport.
   */
  fullHeight?: boolean
  /** ID of the describing element. */
  'aria-describedby'?: string
  /** ID of the labelling element. */
  labelledBy?: string
  /** Optionally control the view mode. If uncontrolled, leave this `undefined`. */
  viewMode?: MarkdownViewMode
  /** If `viewMode` is controlled, this will be called on change. */
  onChangeViewMode?: (newViewMode: MarkdownViewMode) => void
  /**
   * Called when the user presses `Ctrl`/`Cmd` + `Enter`. Should almost always be wired to
   * the same event as clicking the primary `actionButton`.
   */
  onPrimaryAction?: () => void
  /**
   * Minimum number of visible lines of text in the editor.
   * @default 5
   */
  minHeightLines?: number
  /**
   * Maximum number of visible lines of text in the editor. Has no effect if `fullHeight = true`.
   * @default 35
   */
  maxHeightLines?: number
  /**
   * Array of all possible emojis to suggest. Leave `undefined` to disable emoji autocomplete.
   * For lazy-loading suggestions, an async function can be provided instead.
   */
  emojiSuggestions?: SuggestionOptions<Emoji>
  /**
   * Skin tone preference used for rendering applicable emoji suggestions between 1-5.
   * 0 can be used as a default value.
   * See: https://github.com/github/g-emoji-element?tab=readme-ov-file#skin-tones for more information.
   */
  emojiTone?: number
  /**
   * Array of all possible mention suggestions. Leave `undefined` to disable `@`-mention autocomplete.
   * For lazy-loading suggestions, an async function can be provided instead.
   */
  mentionSuggestions?: SuggestionOptions<Mentionable>
  /**
   * Array of all possible references to suggest. Leave `undefined` to disable `#`-reference autocomplete.
   * For lazy-loading suggestions, an async function can be provided instead.
   */
  referenceSuggestions?: SuggestionOptions<Reference>
  /**
   * Uploads a file to a hosting service and returns the URL. If not provided, file uploads
   * will be disabled.
   */
  onUploadFile?: (file: File) => Promise<FileUploadResult>
  /**
   * Array of allowed file types. If `onUploadFile` is defined but this array is not, all
   * file types will be accepted. You can still reject file types by rejecting the `onUploadFile`
   * promise, but setting this array provides a better user experience by preventing the
   * upload in the first place.
   */
  acceptedFileTypes?: FileType[]
  /** Control whether the editor font is monospace. */
  monospace?: boolean
  /** Control whether the input is required. */
  required?: boolean
  /** The name that will be given to the `textarea`. */
  name?: string
  /** To enable the saved replies feature, provide an array of replies. */
  savedReplies?: SavedReply[]
  /** Callback when the saved replies picker is opened */
  onSavedRepliesOpen?: () => void
  /**
   * Control whether URLs are pasted as plain text instead of as formatted links (if the
   * user has selected some text before pasting). Defaults to `false` (URLs will paste as
   * links). This should typically be controlled by user settings.
   *
   * Users can always toggle this behavior by holding `shift` when pasting.
   */
  pasteUrlsAsPlainText?: boolean
  /**
   * Optional error message related to the markdown editor content. Displayed directly
   * below editor. Useful for showing validation or other errors related directly to the
   * markdown provided by the user.
   *
   * Note: This is separate from the error message related to drag-and-drop errors.
   */
  errorMessage?: string
  /** Use hovercards for team mentions in preview mode */
  teamHovercardsEnabled?: boolean
  /** Optional class name */
  className?: string
}

const handleBrand = Symbol()

export interface MarkdownEditorHandle {
  /** Focus on the markdown textarea (has no effect in preview mode). */
  focus: (options?: FocusOptions) => void
  /** Scroll to the editor. */
  scrollIntoView: (options?: ScrollIntoViewOptions) => void
  /** Reset the value and height calculations to initial state. `onChange` will be called with an empty string. */
  reset: () => void
  /**
   * This 'fake' member prevents other types from being assigned to this, thus
   * disallowing broader ref types like `HTMLTextAreaElement`.
   * @private
   */
  [handleBrand]: undefined
}

const CONDENSED_WIDTH_THRESHOLD = 675

/**
 * We want to switch editors from preview mode on cmd/ctrl+shift+P. But in preview mode,
 * there's no input to focus so we have to bind the event to the document. If there are
 * multiple editors, we want the most recent one to switch to preview mode to be the one
 * that we switch back to edit mode, so we maintain a LIFO stack of IDs of editors in
 * preview mode.
 */
let editorsInPreviewMode: string[] = []

/**
 * Markdown textarea with controls & keyboard shortcuts.
 */
const MarkdownEditor = forwardRef<MarkdownEditorHandle, MarkdownEditorProps>(
  (
    {
      value,
      onChange,
      onInputFocus,
      disabled = false,
      placeholder,
      maxLength,
      'aria-describedby': describedBy,
      labelledBy,
      fullHeight,
      onRenderPreview,
      className,
      onPrimaryAction,
      viewMode: controlledViewMode,
      onChangeViewMode: controlledSetViewMode,
      minHeightLines = 5,
      maxHeightLines = 35,
      emojiSuggestions,
      emojiTone,
      mentionSuggestions,
      referenceSuggestions,
      onUploadFile,
      acceptedFileTypes,
      monospace = false,
      required = false,
      name,
      children,
      savedReplies,
      pasteUrlsAsPlainText = false,
      errorMessage,
      teamHovercardsEnabled = false,
      onSavedRepliesOpen = noop,
    },
    ref,
  ) => {
    const [slots, childrenWithoutSlots] = useSlots(children, {
      toolbar: Toolbar,
      actions: Actions,
      label: Label,
      footer: Footer,
    })
    const [uncontrolledViewMode, setUncontrolledViewMode] = useState<MarkdownViewMode>('edit')
    const [view, setView] =
      controlledViewMode === undefined
        ? [uncontrolledViewMode, setUncontrolledViewMode]
        : [controlledViewMode, controlledSetViewMode]

    const [html, setHtml] = useState<SafeHTMLString | null>(null)
    const safeSetHtml = useSafeAsyncCallback(setHtml)

    const previewStale = useRef(true)
    useEffect(() => {
      previewStale.current = true
    }, [value])
    const loadPreview = async () => {
      if (!previewStale.current) return
      previewStale.current = false // set to false before the preview is rendered to prevent multiple concurrent calls
      safeSetHtml(null)
      safeSetHtml(await onRenderPreview(value))
    }
    const useOnInput = isFeatureEnabled('mardown_editor_use_on_input')

    useEffect(() => {
      // we have to be careful here - loading preview sets state which causes a render which can cause an infinite loop,
      // however that should be prevented by previewStale.current being set immediately in loadPreview
      if (view === 'preview' && previewStale.current) void loadPreview()
    })

    /** Input `key` for forcing reset. */
    const [inputKey, setInputKey] = useState(1)
    const reset = () => {
      onChange('')
      setInputKey(key => key + 1)
    }

    const inputRef = useRef<HTMLTextAreaElement>(null)
    useImperativeHandle(ref, () => ({
      focus: opts => inputRef.current?.focus(opts),
      scrollIntoView: opts => containerRef.current?.scrollIntoView(opts),
      reset: () => reset(),
      // satisfy the type monster
      [handleBrand]: undefined,
    }))

    const inputHeight = useRef(0)

    if (inputRef.current && inputRef.current.offsetHeight) inputHeight.current = inputRef.current.offsetHeight

    const onInputChange = useCallback(
      (e: React.ChangeEvent<HTMLTextAreaElement>) => {
        onChange(e.target.value)
      },
      [onChange],
    )

    const emitChange = useSyntheticChange({inputRef, fallbackEventHandler: onInputChange})

    const fileHandler = useFileHandling({
      emitChange,
      value,
      inputRef,
      disabled,
      onUploadFile,
      acceptedFileTypes,
    })

    const isUploadingFiles = fileHandler?.uploadProgress !== undefined
    const listEditor = useListEditing({emitChange})
    const indenter = useIndenting({emitChange})

    const formattingToolsRef = useRef<FormattingTools>(null)

    // use state instead of ref since we need to recalculate when the element mounts
    const containerRef = useRef<HTMLDivElement>(null)

    const [condensed, setCondensed] = useState(false)
    const onResize = useCallback(
      // it's fine that this isn't debounced because calling setCondensed with the current value will not trigger a render
      () => setCondensed(containerRef.current !== null && containerRef.current.clientWidth < CONDENSED_WIDTH_THRESHOLD),
      [],
    )
    useResizeObserver(onResize, containerRef)

    // workaround for Safari bug where layout is otherwise not recalculated
    useIsomorphicLayoutEffect(() => {
      const container = containerRef.current
      if (!container) return

      const parent = container.parentElement
      const nextSibling = containerRef.current.nextSibling
      parent?.removeChild(container)
      parent?.insertBefore(container, nextSibling)
    }, [condensed])

    // the ID must be unique for each instance while remaining constant across renders
    const id = useId()
    const descriptionId = `${id}-description`

    const savedRepliesRef = useRef<SavedRepliesHandle>(null)

    const savedRepliesContext = useMemo(
      () =>
        savedReplies
          ? {
              savedReplies,
              onSelect: (reply: SavedReply) => {
                // need to wait a tick to run after the selectmenu finishes closing
                requestAnimationFrame(() => emitChange(reply.content))
              },
              onOpen: onSavedRepliesOpen,
              ref: savedRepliesRef,
            }
          : null,
      [emitChange, onSavedRepliesOpen, savedReplies],
    )

    const inputCompositionProps = useIgnoreKeyboardActionsWhileComposing(
      (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
        const format = formattingToolsRef.current
        if (disabled) return

        // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        if (e.ctrlKey && e.key === '.') {
          // saved replies are always Control, even on Mac
          savedRepliesRef.current?.openMenu()
          e.preventDefault()
          e.stopPropagation()
        } else if (isModifierKey(e)) {
          // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
          if (e.key === 'Enter' && !isUploadingFiles) onPrimaryAction?.()
          // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
          else if (e.key === 'b') format?.bold()
          // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
          else if (e.key === 'i') format?.italic()
          // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
          else if (e.shiftKey && e.key === '.') format?.quote()
          // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
          else if (e.key === 'e') format?.code()
          // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
          else if (e.key === 'k') format?.link()
          // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
          else if (e.key === '8') format?.unorderedList()
          // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
          else if (e.shiftKey && e.key === '7') format?.orderedList()
          // on some layouts, such as AZERTY, the key is registered as uppercase when shift is pressed
          // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
          else if (e.shiftKey && ['l', 'L'].includes(e.key)) format?.taskList()
          // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
          else if (e.shiftKey && ['p', 'P'].includes(e.key)) setView?.('preview')
          else return

          e.preventDefault()
          e.stopPropagation()
        } else {
          listEditor.onKeyDown(e)
          indenter.onKeyDown(e)
        }
      },
    )

    useEffect(() => {
      if (view === 'preview') {
        editorsInPreviewMode.push(id)

        const handler = (e: KeyboardEvent) => {
          if (
            !e.defaultPrevented &&
            editorsInPreviewMode.at(-1) === id &&
            isModifierKey(e) &&
            e.shiftKey &&
            // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
            e.key === 'p'
          ) {
            setView?.('edit')
            // eslint-disable-next-line @eslint-react/web-api/no-leaked-timeout
            setTimeout(() => inputRef.current?.focus())
            e.preventDefault()
          }
        }
        document.addEventListener('keydown', handler)

        return () => {
          document.removeEventListener('keydown', handler)
          // Performing the filtering in the cleanup callback allows it to happen also when
          // the user clicks the toggle button, not just on keyboard shortcut
          editorsInPreviewMode = editorsInPreviewMode.filter(id_ => id_ !== id)
        }
      }
    }, [view, setView, id])

    // If we don't memoize the context object, every child will rerender on every render even if memoized
    const context = useMemo(
      () => ({
        disabled,
        formattingToolsRef,
        condensed,
        required,
        fileDraggedOver: fileHandler?.isDraggedOver ?? false,
        fileUploadProgress: fileHandler?.uploadProgress,
        uploadButtonProps: fileHandler?.clickTargetProps ?? null,
        errorMessage: fileHandler?.errorMessage,
        previewMode: view === 'preview',
      }),
      [
        disabled,
        condensed,
        required,
        fileHandler?.isDraggedOver,
        fileHandler?.uploadProgress,
        fileHandler?.clickTargetProps,
        fileHandler?.errorMessage,
        view,
      ],
    )

    // We are using MarkdownEditorContext instead of the built-in Slots context because Slots' context is not typesafe
    return (
      <MarkdownEditorContext.Provider value={context}>
        <fieldset
          aria-disabled={disabled /* if we set disabled={true}, we can't enable the buttons that should be enabled */}
          className={clsx(styles.fieldSet, fullHeight && styles.fullHeight)}
        >
          <FormattingTools ref={formattingToolsRef} forInputId={id} />
          <div className={styles.hidden}>{childrenWithoutSlots}</div>

          {slots.label}

          <div ref={containerRef} className={styles.container}>
            {errorMessage && (
              <Flash variant="danger" className="mb-2">
                <StopIcon />
                {errorMessage}
              </Flash>
            )}
            <div
              className={clsx(
                className,
                view === 'edit' ? styles.inputWrapper : styles.previewWrapper,
                disabled && styles.disabled,
                fullHeight && styles.fullHeight,
              )}
            >
              <span className="sr-only" id={descriptionId} aria-live="polite">
                Markdown input:
                {view === 'preview' ? ' preview mode selected.' : ' edit mode selected.'}
              </span>
              <header className={styles.header}>
                <div className={styles.viewSwitchWrapper}>
                  <ViewSwitch
                    selectedView={view}
                    onViewSelect={setView}
                    disabled={fileHandler?.uploadProgress !== undefined}
                    onLoadPreview={loadPreview}
                  />
                  <div className={styles.viewSwitchBorder} />
                </div>

                <SavedRepliesContext.Provider value={savedRepliesContext}>
                  {view === 'edit' &&
                    (slots.toolbar ?? (
                      <CoreToolbar>
                        <DefaultToolbarButtons />
                      </CoreToolbar>
                    ))}
                </SavedRepliesContext.Provider>
              </header>
              <MarkdownInput
                value={value}
                onChange={!useOnInput ? onInputChange : undefined}
                onInput={useOnInput ? onInputChange : undefined}
                onFocus={onInputFocus}
                emojiSuggestions={emojiSuggestions}
                emojiTone={emojiTone}
                mentionSuggestions={mentionSuggestions}
                referenceSuggestions={referenceSuggestions}
                disabled={disabled}
                placeholder={placeholder}
                labelledBy={labelledBy}
                aria-describedby={describedBy ? `${descriptionId} ${describedBy}` : descriptionId}
                id={id}
                maxLength={maxLength}
                ref={inputRef}
                fullHeight={fullHeight}
                isDraggedOver={fileHandler?.isDraggedOver ?? false}
                minHeightLines={minHeightLines}
                maxHeightLines={maxHeightLines}
                visible={view === 'edit'}
                monospace={monospace}
                required={required}
                name={name}
                pasteUrlsAsPlainText={pasteUrlsAsPlainText}
                key={inputKey}
                {...inputCompositionProps}
                {...fileHandler?.pasteTargetProps}
                {...fileHandler?.dropTargetProps}
              />
              <div role="alert">
                {view === 'edit' && fileHandler?.errorMessage && <ErrorMessage message={fileHandler.errorMessage} />}
              </div>
              {view === 'preview' && (
                <div
                  aria-live="polite"
                  tabIndex={-1}
                  className={clsx(styles.previewViewerWrapper, fullHeight && styles.fullHeight)}
                  style={{minHeight: inputHeight.current}}
                >
                  <h2 className={styles.previewHeader}>Rendered Markdown Preview</h2>
                  <MarkdownViewer
                    verifiedHTML={html || ('Nothing to preview' as SafeHTMLString)}
                    loading={html === null}
                    teamHovercardsEnabled={teamHovercardsEnabled}
                    openLinksInNewTab
                  />
                </div>
              )}
            </div>
            {slots.footer ?? <CoreFooter>{isValidElement(slots.actions) && slots.actions.props.children}</CoreFooter>}
          </div>
        </fieldset>
      </MarkdownEditorContext.Provider>
    )
  },
)
MarkdownEditor.displayName = 'MarkdownEditor'

export default MarkdownEditor

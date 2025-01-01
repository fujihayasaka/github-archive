import {Spinner} from '@primer/react'
import {useMemo, useRef} from 'react'
import {type SafeHTMLString, SafeHTMLBox} from '@github-ui/safe-html'
import {TaskListItems} from '@github-ui/use-tasklist/components/TaskListItems'
import styles from './NewMarkdownViewer.module.css'
import {clsx} from 'clsx'
import {useQuerySelectorAll, useTasklistData} from '@github-ui/use-tasklist'
import {useLinkInterception} from '@github-ui/use-link-interception'
import type {OnConvertToIssueCallback, OnConvertToSubIssueCallback} from './types'

type CoreMarkdownViewerProps = {
  /** Show a loading spinner instead of content. */
  loading?: boolean
  /**
   * Set the rendered HTML of the viewer. To prevent XSS, ensure that the source of this
   * HTML is trusted!
   */
  verifiedHTML: SafeHTMLString
  /**
   * Called when the user clicks a link element. This can be used to intercept the click
   * and provide custom routing. Note that this is a native HTML `MouseEvent` and not a
   * `React.ClickEvent`.
   */
  onLinkClick?: (event: MouseEvent) => void
  onConvertToIssue?: OnConvertToIssueCallback
  onConvertToSubIssue?: OnConvertToSubIssueCallback
  openLinksInNewTab?: boolean
  /**
   * Additional class name to apply to the container element.
   */
  className?: string
}

export type InteractiveMarkdownViewerProps = CoreMarkdownViewerProps & {
  /**
   * The markdown the HTML was rendered from. This is not used for viewing, only as a source
   * for change events.
   */
  markdownValue: string
  /**
   * Called when the user interacts and updates the Markdown. The rendered Markdown is
   * updated eagerly - if the request fails, a rejected Promise should be returned by
   * this handler. In that case, the viewer will revert the visual change.
   *
   * If the change is handled by an async API request (as it typically will be in production
   * code), the viewer should be `disabled` while the request is pending to avoid conflicts.
   * To allow users to check multiple boxes rapidly, the API request should be debounced (an
   * ideal debounce duration is about 1 second).
   */
  onChange?: (markdown: string) => void | Promise<void>
  /** Control whether interaction is disabled. */
  disabled?: boolean
  viewerCanUpdate?: boolean
}

type NoninteractiveMarkdownViewerProps = CoreMarkdownViewerProps & {
  // This is externally useless, but internally it lets us use unpacking to get the props.
  // If a prop was present only on one member of the type union, Typescript would treat it as
  // though it doesn't exist at all until you discriminate which type the props are.
  markdownValue?: undefined
  onChange?: undefined
  disabled?: undefined
  viewerCanUpdate?: undefined
}

export type NewMarkdownProps = NoninteractiveMarkdownViewerProps | InteractiveMarkdownViewerProps

export const NewMarkdownViewer = ({
  verifiedHTML,
  markdownValue = '',
  onChange: externalOnChange,
  onConvertToIssue,
  onConvertToSubIssue,
  onLinkClick,
  openLinksInNewTab = false,
  loading = false,
  disabled,
  viewerCanUpdate,
  className,
}: NewMarkdownProps) => {
  const htmlContainerRef = useRef<HTMLDivElement>(null)
  const tasklists = useQuerySelectorAll(
    htmlContainerRef,
    // Select all task lists that are not nested within another task list, since
    // we recursively process nested task lists.
    '.contains-task-list:not(.contains-task-list .contains-task-list)',
    verifiedHTML,
  )

  const {tasklistData, nestedItems, setTasklistData} = useTasklistData(htmlContainerRef.current, tasklists)

  useLinkInterception({
    htmlContainerRef,
    onLinkClick,
    openLinksInNewTab,
  })

  const htmlContent = useMemo(() => {
    const classes = ['markdown-body', styles['safe-html-box']]
    if (className) {
      classes.push(className)
    }
    return <SafeHTMLBox ref={htmlContainerRef} className={clsx(classes)} html={verifiedHTML} />
  }, [className, verifiedHTML])

  return loading ? (
    <div className={clsx(styles.spinner)}>
      <Spinner aria-label="Loading markdown content..." />
    </div>
  ) : (
    <>
      {htmlContent}

      {tasklists.length > 0 && (
        <TaskListItems
          tasklists={tasklists}
          markdownValue={markdownValue}
          externalOnChange={externalOnChange}
          onConvertToIssue={onConvertToIssue}
          onConvertToSubIssue={onConvertToSubIssue}
          tasklistData={tasklistData}
          setTasklistData={setTasklistData}
          nestedItems={nestedItems}
          disabled={disabled || !externalOnChange}
          viewerCanUpdate={viewerCanUpdate}
        />
      )}
    </>
  )
}

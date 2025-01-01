import {debounce} from '@github/mini-throttle'
import {type InteractiveMarkdownViewerProps, NewMarkdownViewer} from '@github-ui/markdown-viewer/NewMarkdownViewer'
import type {SafeHTMLString} from '@github-ui/safe-html'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {Text} from '@primer/react'
import React, {useCallback, useMemo, useRef} from 'react'

import {LABELS} from '../../constants/labels'
import {TEST_IDS} from '../../constants/test-ids'

type IssueMarkdownViewerProps = {
  html: SafeHTMLString
  markdown: string
  viewerCanUpdate: boolean
  dataTestId?: string
  onSave: (newBody: string, onCompleted: () => void, onError: () => void) => void
  /**
   * Called when the user clicks a link element. This can be used to intercept the click
   * and provide custom routing.
   *
   * Note that this is a native HTML `MouseEvent` and not a `React.ClickEvent`.
   */
  onLinkClick?: (event: MouseEvent) => void
  onConvertToIssue?: InteractiveMarkdownViewerProps['onConvertToIssue']
  onConvertToSubIssue?: InteractiveMarkdownViewerProps['onConvertToSubIssue']
  createdViaEmail?: boolean
}

export const IssueMarkdownViewer = ({
  html,
  markdown,
  viewerCanUpdate,
  onSave,
  onLinkClick,
  dataTestId = TEST_IDS.markdownBody,
  onConvertToIssue,
  onConvertToSubIssue,
  createdViaEmail = false,
}: IssueMarkdownViewerProps) => {
  const {addToast} = useToastContext()
  const [isSaving, setIsSaving] = React.useState(false)

  const finishEditing = useCallback(
    (onSuccess: () => void, onError: () => void, error?: string) => {
      setIsSaving(false)
      if (error) {
        onError()

        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message: error,
        })
      } else {
        onSuccess()
      }
    },
    [addToast],
  )

  const onPerformChange = useCallback(
    (body: string) => {
      const promise = new Promise<void>((resolve, reject) => {
        setIsSaving(true)
        onSave(
          body,
          () => finishEditing(resolve, reject),
          () => finishEditing(resolve, reject, 'Could not update issue comment'),
        )
      })

      return promise
    },
    [finishEditing, onSave],
  )

  // useRef is used here to make sure we don't call onPerformChange with an outdated function
  // in case the issue has changed for example in between
  const onPerformChangeRef = useRef(onPerformChange)
  useLayoutEffect(() => {
    onPerformChangeRef.current = onPerformChange
  }, [onPerformChange])

  // eslint-disable-next-line react-compiler/react-compiler
  const onChange = useMemo(() => debounce((nextValue: string) => onPerformChangeRef.current(nextValue), 500), [])

  const innerBody: JSX.Element = useMemo(() => {
    if (html && html.length > 0) {
      return (
        <NewMarkdownViewer
          disabled={!viewerCanUpdate || isSaving}
          viewerCanUpdate={viewerCanUpdate}
          verifiedHTML={html}
          markdownValue={markdown}
          onChange={onChange}
          onConvertToIssue={onConvertToIssue}
          onConvertToSubIssue={onConvertToSubIssue}
          onLinkClick={onLinkClick}
          className={createdViaEmail ? 'email-format' : undefined}
        />
      )
    } else {
      return (
        <Text sx={{color: 'fg.muted', m: 0, fontStyle: 'italic', fontSize: 1}}>{LABELS.noDescriptionProvided}</Text>
      )
    }
  }, [
    createdViaEmail,
    html,
    isSaving,
    markdown,
    onChange,
    onConvertToIssue,
    onConvertToSubIssue,
    onLinkClick,
    viewerCanUpdate,
  ])

  return (
    <div
      data-testid={dataTestId}
      data-team-hovercards-enabled
      className="markdown-body"
      // Make links from project -> project hard navigate if the user chooses to open in same tab
      // https://github.com/github/memex/issues/9202#issuecomment-1085941126
      data-turbolinks="false"
    >
      {innerBody}
    </div>
  )
}

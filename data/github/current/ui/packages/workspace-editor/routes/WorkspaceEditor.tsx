import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {WebCommitDialogState} from '@github-ui/web-commit-dialog'
import {PageLayout, useResizeObserver} from '@primer/react'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {Banner} from '../components/Banner'
import {CommitPanel} from '../components/CommitPanel'
import {Header} from '../components/Header'
import {MainContent} from '../components/MainContent'
import {RightSidePanel} from '../components/RightSidePanel'
import {useFilesContext} from '../contexts/FilesContext'
import {useTerminalContext} from '../contexts/TerminalContext'
import {useWorkspaceEditorUIDispatch, useWorkspaceEditorUIState} from '../contexts/WorkspaceEditorUIContext'
import {useLocalSuggestionState} from '../hooks/use-local-suggestion-state'
import {useSuggestions} from '../hooks/use-suggestions'
import {useTwoWayFileSyncer} from '../hooks/use-two-way-file-syncer'
import {useFileSyncerClient} from '../lsp/use-file-syncer-client'
import {initialPathQueryParam, removeQueryParam} from '../utilities/query-params'
import {countActionableSuggestions} from '../utilities/suggestion-helpers'
import type {WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'
import {RightPanelType} from '../utilities/workspace-editor-ui-reducer'

const appOffsetTop = (rootElement?: HTMLElement | null) => {
  return rootElement?.getBoundingClientRect().top ?? 0
}

function useAppOffsetTop() {
  const rootRef = useRef<HTMLDivElement | null>(null)
  const [offsetTop, setOffsetTop] = useState(() => appOffsetTop(rootRef?.current))
  const resizeObserver = useCallback(() => {
    setOffsetTop(appOffsetTop(rootRef?.current))
  }, [])

  useResizeObserver(resizeObserver, rootRef)

  return {offsetTop, rootRef}
}

function useHeaderHeight() {
  const headerRef = useRef<HTMLDivElement | null>(null)
  const [headerHeight, setHeaderHeight] = useState(() => headerRef?.current?.clientHeight ?? 0)
  const resizeObserver = useCallback(() => {
    setHeaderHeight(headerRef?.current?.clientHeight ?? 0)
  }, [])

  useResizeObserver(resizeObserver, headerRef)
  return {headerHeight, headerRef}
}

export function WorkspaceEditor() {
  const {getFileStatuses} = useFilesContext()
  const {
    dispatch,
    state: {terminalVisibility, previewUrl, codespaceData},
  } = useTerminalContext()
  const {rightPanel} = useWorkspaceEditorUIState()
  const uiDispatch = useWorkspaceEditorUIDispatch()
  const [commitDialogState, setCommitDialogState] = useState<WebCommitDialogState>('closed')
  const commitButtonRef = useRef<HTMLButtonElement>(null)

  const terminalHeaderButtonRef = useRef<HTMLButtonElement>(null)
  const suggestionsHeaderButtonRef = useRef<HTMLButtonElement>(null)
  const copilotHeaderButtonRef = useRef<HTMLButtonElement>(null)
  const {offsetTop, rootRef} = useAppOffsetTop()
  const {isNewFilePage, pullRequestNumber} = useRoutePayload<WorkspaceEditorRoutePayload>()

  const onCommitClick = useCallback(() => {
    setCommitDialogState('pending')
  }, [])

  const onCommitPanelClose = useCallback(() => {
    setCommitDialogState('closed')
  }, [])

  useEffect(() => {
    if (!isNewFilePage) {
      removeQueryParam(initialPathQueryParam)
    }
  }, [isNewFilePage])

  const onTerminalVisibilityChange = useCallback(() => {
    const visibility = terminalVisibility === 'visible' ? 'hidden' : 'visible'
    dispatch({
      type: 'TOGGLE_TERMINAL_VISIBILITY',
      terminalVisibility: visibility,
    })

    if (visibility === 'hidden') {
      terminalHeaderButtonRef.current?.focus()
    }
  }, [terminalVisibility, dispatch])

  const isCodespaceReady = codespaceData.codespaceState === 'ready'

  const {getFileSyncerClient: getOneWayFileSyncerClient} = useFileSyncerClient(
    codespaceData,
    codespaceData.remoteProvider,
  )

  const {suggestionMap, areSuggestionsFetched} = useSuggestions()
  const {getDismissedSuggestions} = useLocalSuggestionState()
  const actionableSuggestionsCount = useMemo(
    () => countActionableSuggestions(suggestionMap, getDismissedSuggestions()),
    [suggestionMap, getDismissedSuggestions],
  )

  const twoWayFileSyncerEnabled = useFeatureFlag('hadron_use_two_way_file_syncer')

  // We don't want to pop the suggestion panel open every time the number of actionable suggestions changes,
  // but we do need to make sure to re-calculate whether it should be open when the promise to fetch suggestions
  // resolves.
  // Once the we have finished fetching suggestions and calculated the actionable suggestions count, we shouldn't
  // reopen the suggestion panel automatically again.
  const hasAttemptedToOpenSuggestions = useRef(false)
  useEffect(() => {
    if (hasAttemptedToOpenSuggestions.current) return
    if (areSuggestionsFetched) {
      hasAttemptedToOpenSuggestions.current = true
    }
    if (actionableSuggestionsCount > 0 && rightPanel === RightPanelType.None) {
      uiDispatch({
        type: 'TOGGLE_RIGHT_PANEL',
        rightPanel: RightPanelType.Suggestions,
        rightPanelButton: suggestionsHeaderButtonRef.current || undefined,
      })
    }
  }, [actionableSuggestionsCount, areSuggestionsFetched, uiDispatch, suggestionsHeaderButtonRef, rightPanel])

  useTwoWayFileSyncer(codespaceData, twoWayFileSyncerEnabled)

  // Disable one way file syncer if two way file syncer is enabled
  const getFileSyncerClient = twoWayFileSyncerEnabled ? () => null : getOneWayFileSyncerClient

  const {headerHeight, headerRef} = useHeaderHeight()

  return (
    <div ref={rootRef} data-hpc>
      <PageLayout
        containerWidth="full"
        padding="condensed"
        rowGap="condensed"
        columnGap="condensed"
        sx={{
          '--workspace-editor-offset-top': `${offsetTop}px`,
          '--workspace-editor-header-height': `${headerHeight}px`,
          '--workspace-editor-padding-height': 'calc(3 * 8px)',
          '--workspace-editor-content-height': `calc(var(--sticky-pane-height) - var(--workspace-editor-offset-top) - var(--workspace-editor-header-height) - var(--workspace-editor-padding-height))`,
          '--workspace-editor-terminal-height': '300px',
          '--workspace-editor-terminal-header-height': '48px',
          '--workspace-editor-terminal-pane-height':
            'calc(var(--workspace-editor-terminal-height) - var(--workspace-editor-terminal-header-height))',
          height: 'calc(var(--sticky-pane-height) - var(--workspace-editor-offset-top))',
          bg: 'canvas.inset',
          padding: 'var(--base-size-8)',
        }}
      >
        <PageLayout.Header divider="none" padding="none" sx={{marginBottom: 'var(--base-size-8)'}}>
          <div ref={headerRef}>
            <Header
              pullRequestNumber={pullRequestNumber}
              onCommitClick={onCommitClick}
              copilotHeaderButtonRef={copilotHeaderButtonRef}
              suggestionsHeaderButtonRef={suggestionsHeaderButtonRef}
              actionableSuggestionsCount={actionableSuggestionsCount}
              commitButtonRef={commitButtonRef}
              isCodespaceReady={isCodespaceReady}
              onTerminalVisibilityChange={onTerminalVisibilityChange}
              forwardedUrl={previewUrl}
            />
            <Banner />
          </div>
        </PageLayout.Header>
        <PageLayout.Content
          as="div"
          padding="none"
          width="full"
          sx={{
            overflowY: 'hidden',
          }}
        >
          <MainContent getFileSyncerClient={getFileSyncerClient} />
        </PageLayout.Content>
        <RightSidePanel codespaceData={codespaceData} getFileSyncerClient={getFileSyncerClient} />
      </PageLayout>
      {commitDialogState !== 'closed' && (
        <CommitPanel
          dialogState={commitDialogState}
          fileStatuses={getFileStatuses()}
          setDialogState={setCommitDialogState}
          onClose={onCommitPanelClose}
          commitButtonRef={commitButtonRef}
        />
      )}
    </div>
  )
}

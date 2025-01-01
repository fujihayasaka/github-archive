import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {PageLayout, useResizeObserver} from '@primer/react'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {Banner} from '../../workspace-editor/components/Banner'
import {initialPathQueryParam, removeQueryParam} from '../../workspace-editor/utilities/query-params'
import {Header} from '../components/Header'
import {IterateModal} from '../components/IterateModal'
import {MainContent} from '../components/MainContent'
import {useTerminalContext} from '../contexts/TerminalContext'
import {useFileSyncer} from '../hooks/use-file-syncer'
import {useWorkbench} from '../hooks/use-workbench'
import type {WorkbenchRoutePayload} from '../types/workbench-types'
import styles from './Workbench.module.css'

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

const suggestions = [
  'Add a refresh button to automatically refresh the satellite image and weather forecast based on the latest data',
  "Add severe weather alerts for the user's current location",
]

export function Workbench() {
  const {
    state: {codespaceData},
  } = useTerminalContext()

  const [controlMode, setControlMode] = useState('floating')
  const {offsetTop, rootRef} = useAppOffsetTop()
  const {headerHeight, headerRef} = useHeaderHeight()

  const {
    workbench,
    copilot: {ssoOrganizations, apiURL, currentTopic},
    isNewFilePage,
  } = useRoutePayload<WorkbenchRoutePayload>()

  const authTokenProvider = useMemo(
    () => new CopilotAuthTokenProvider(ssoOrganizations.map(org => org.id)),
    [ssoOrganizations],
  )

  const workbenchParams = useMemo(
    () => ({
      workbench,
      apiURL,
      authTokenProvider,
    }),
    [workbench, apiURL, authTokenProvider],
  )

  const {previousRefinements, isFetching, currentFiles, submitPrompt} = useWorkbench(workbenchParams)

  useEffect(() => {
    if (!isNewFilePage) {
      removeQueryParam(initialPathQueryParam)
    }
  }, [isNewFilePage])

  useFileSyncer(codespaceData)

  if (!authTokenProvider) return null

  return (
    <div ref={rootRef} data-hpc>
      <PageLayout
        containerWidth="full"
        padding="condensed"
        rowGap="condensed"
        columnGap="condensed"
        className={styles.pageLayout}
        sx={{
          // Account for uncontrollable UI like the staff bar
          '--workspace-editor-offset-top': `${offsetTop}px`,
          // The header height can change if there are banners or if the content wraps
          '--workspace-editor-header-height': `${headerHeight}px`,
        }}
      >
        <PageLayout.Header divider="none" padding="none" className="mb-2">
          <div ref={headerRef}>
            <Header openIterationModal={() => setControlMode('floating')} />
            <Banner />
          </div>
        </PageLayout.Header>
        <PageLayout.Content as="div" padding="none" width="full" className="overflow-y-hidden">
          <MainContent copilotCurrentTopic={currentTopic} />
        </PageLayout.Content>
      </PageLayout>
      {controlMode === 'floating' && (
        <IterateModal
          closeModal={() => setControlMode('panel')}
          submitPrompt={submitPrompt}
          previousRefinements={previousRefinements}
          isFetching={isFetching}
          suggestions={suggestions}
          step={Object.keys(currentFiles).length ? 'refine' : 'generate'}
        />
      )}
    </div>
  )
}

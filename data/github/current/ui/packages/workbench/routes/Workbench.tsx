import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useViewport} from '@github-ui/use-viewport'
import {initialPathQueryParam, removeQueryParam} from '@github-ui/workspace-editor/utilities/query-params'
import {Dialog, PageLayout, useResizeObserver} from '@primer/react'
import {clsx} from 'clsx'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'

import CreateRepositoryDialog from '../components/CreateRepositoryDialog'
import {FilteredContentModal} from '../components/FilteredContentModal'
import {Header} from '../components/Header'
import {MainContent} from '../components/MainContent'
import {SidePanel} from '../components/SidePanel/SidePanel'
import {TargetedEditsInput} from '../components/TargetedEditsInput'
import {useContentFilter} from '../contexts/ContentFilterContext'
import {ErrorsProvider} from '../contexts/ErrorsContext'
import {PublishingProvider} from '../contexts/PublishingContext'
import {useTargetedEditsContext} from '../contexts/TargetedEditsContext'
import {useTerminalContext} from '../contexts/TerminalContext'
import {useWorkbenchUI} from '../contexts/WorkbenchUIContext'
import {type RepositoryVisibility, useWorkbench} from '../hooks/use-workbench'
import type {WorkbenchRoutePayload} from '../types/workbench-types'
import {SparkAuthTokenProvider} from '../utilities/auth-token-provider'
import styles from './Workbench.module.css'

const appOffsetTop = (rootElement?: HTMLElement | null) => {
  const top = rootElement?.getBoundingClientRect().top ?? 0
  return top > 0 ? top : 0
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

function useHideGlobalNav() {
  const initialHeaderHiddenState = useRef<boolean | null>(null)

  useEffect(() => {
    const headerDiv: HTMLElement | null = document.querySelector('.AppHeader')
    if (!headerDiv) return
    if (initialHeaderHiddenState.current === null) {
      initialHeaderHiddenState.current = headerDiv.hidden
    }
    // Don't do anything if the header is already hidden
    if (headerDiv.hidden) return

    headerDiv.hidden = true

    // On cleanup, restore the header to its original state
    return () => {
      if (headerDiv && initialHeaderHiddenState.current !== null) {
        headerDiv.hidden = initialHeaderHiddenState.current
      }
    }
  }, [])
}

export function Workbench() {
  const [selectedPanel, setSelectedPanel] = useState<'iterate' | 'theme' | 'data' | 'ai' | 'assets' | 'logs'>('iterate')

  const {sidePanelOpen, workingMode, setWorkingMode, createRepositoryModelOpen, setCreateRepositoryModelOpen} =
    useWorkbenchUI()
  const {offsetTop, rootRef} = useAppOffsetTop()
  const {headerHeight, headerRef} = useHeaderHeight()
  useHideGlobalNav()

  const {
    copilot: {ssoOrganizations, currentTopic},
    isNewFilePage,
  } = useRoutePayload<WorkbenchRoutePayload>()

  const {
    state: {codespaceData},
  } = useTerminalContext()

  const authTokenProvider = useMemo(() => {
    if (copilotFeatureFlags.sparkAuthTokenEndpoint) {
      return new SparkAuthTokenProvider(ssoOrganizations.map(org => org.id))
    } else {
      return new CopilotAuthTokenProvider(ssoOrganizations.map(org => org.id))
    }
  }, [ssoOrganizations])

  const workbenchData = useWorkbench()
  const {submitPrompt, isMobileSidebarOpen, setIsMobileSidebarOpen, createRepository, friendlyName} = workbenchData

  useEffect(() => {
    if (!isNewFilePage) {
      removeQueryParam(initialPathQueryParam)
    }
  }, [isNewFilePage])

  const {selectedElement} = useTargetedEditsContext()
  const {width: viewportWidth} = useViewport()

  useEffect(() => {
    // If the viewport resizes smaller than the large breakpoint (1012), we can't show the split view
    if (viewportWidth && viewportWidth < 1012 && workingMode === 'split') {
      setWorkingMode('preview')
    }
  }, [setWorkingMode, viewportWidth, workingMode])

  const {isFilteredModalOpen, filterExplanationContent, filteredCategories, setIsFilteredModalOpen} = useContentFilter()

  const handleCreateRepositoryClose = useCallback(() => {
    setCreateRepositoryModelOpen(false)
  }, [setCreateRepositoryModelOpen])
  const handleCreateRepository = useCallback(
    async (repositoryName: string, visibility: RepositoryVisibility) => {
      await createRepository(repositoryName, visibility)
      setCreateRepositoryModelOpen(false)
    },
    [createRepository, setCreateRepositoryModelOpen],
  )

  if (!authTokenProvider) return null

  return (
    <PublishingProvider>
      <ErrorsProvider>
        <div ref={rootRef} data-hpc>
          <PageLayout
            containerWidth="full"
            padding="none"
            rowGap="condensed"
            columnGap="none"
            className={styles.pageLayout}
            style={{
              // Account for uncontrollable UI like the staff bar
              '--workspace-editor-offset-top': `${offsetTop}px`,
              // The header height can change if there are banners or if the content wraps
              '--workspace-editor-header-height': `${headerHeight}px`,
            }}
          >
            <PageLayout.Header className="mb-0">
              <Header
                headerRef={headerRef}
                isReady={codespaceData.codespaceState === 'ready'}
                workbenchData={workbenchData}
              />
            </PageLayout.Header>
            <PageLayout.Pane
              position="start"
              aria-label="Side pane"
              className={clsx(styles.pagePane, {[styles.pagePaneExpanded]: sidePanelOpen}, 'd-none d-sm-block')}
              width={{
                // 100% is a valid value, but Pane expects {string}px, using workaround until I find better solution
                // @ts-expect-error See above
                default: '100%',
                // @ts-expect-error See above
                min: '100%',
                // @ts-expect-error See above
                max: '100%',
              }}
            >
              <div className={styles.sidePanelWrapper}>
                <SidePanel
                  workbenchData={workbenchData}
                  selectedPanel={selectedPanel}
                  setSelectedPanel={setSelectedPanel}
                />
              </div>
            </PageLayout.Pane>

            <PageLayout.Content
              as="div"
              padding="none"
              width="full"
              className={clsx(styles.pageContent, {[styles.contentFullWidth]: !sidePanelOpen})}
            >
              <MainContent copilotCurrentTopic={currentTopic} workbenchData={workbenchData} />
            </PageLayout.Content>
          </PageLayout>
          {isFilteredModalOpen && (
            <FilteredContentModal
              content={filterExplanationContent}
              filteredCategories={filteredCategories}
              onClose={() => setIsFilteredModalOpen(false)}
            />
          )}
          {isMobileSidebarOpen && (
            <Dialog
              title="Edit your spark"
              position={{narrow: 'bottom', regular: 'bottom'}}
              height="large"
              width="xlarge"
              className={clsx(styles.sidePanelDialog, 'hide-md hide-lg hide-xl height-full')}
              onClose={() => setIsMobileSidebarOpen(false)}
            >
              <div className="height-full">
                <SidePanel
                  workbenchData={workbenchData}
                  selectedPanel={selectedPanel}
                  setSelectedPanel={setSelectedPanel}
                />
              </div>
            </Dialog>
          )}
          {createRepositoryModelOpen && (
            <CreateRepositoryDialog
              name={friendlyName}
              ownerLogin={workbenchData.workbench.billableOwner.login}
              onCancel={handleCreateRepositoryClose}
              onSubmit={handleCreateRepository}
            />
          )}
          {selectedElement && <TargetedEditsInput element={selectedElement} submitPrompt={submitPrompt} />}
        </div>
      </ErrorsProvider>
    </PublishingProvider>
  )
}

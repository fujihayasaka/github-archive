import {isFeatureEnabled} from '@github-ui/feature-flags'
import {Banner} from '@github-ui/workspace-editor/components/Banner'
import {
  BrowserIcon,
  BugIcon,
  CodeIcon,
  DeviceMobileIcon,
  GearIcon,
  KebabHorizontalIcon,
  MarkGithubIcon,
  RepoIcon,
  RepoPushIcon,
  SidebarCollapseIcon,
  SidebarExpandIcon,
  SyncIcon,
} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton, Label, Link, SegmentedControl, Stack} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {clsx} from 'clsx'
import React, {Suspense, useCallback, useMemo, useRef, useState} from 'react'

import {useTargetedEditsContext} from '../contexts/TargetedEditsContext'
import {useTerminalContext} from '../contexts/TerminalContext'
import {useWorkbenchUI} from '../contexts/WorkbenchUIContext'
import type {UseWorkbenchReturn} from '../hooks/use-workbench'
import type {WorkingMode} from '../types/workbench-types'
import {SparklePencilIcon} from './CustomIcons'
import {PublishDropdown} from './Deployment/PublishDropdown'
import {OpenCodespace} from './EditorHeader/OpenCodespace'
import styles from './Header.module.css'
import {SettingsPanel} from './SettingsPanel'
import {SparkSwitcher} from './SparkSwitcher'
import {SplitViewIcon} from './SplitViewIcon'
import {TargetIcon} from './TargetIcon'

export interface HeaderProps {
  headerRef: React.RefObject<HTMLDivElement>
  isReady: boolean
  workbenchData: UseWorkbenchReturn
}

const DebugDialog = React.lazy(() => import('./Debug/DebugDialog'))

export const Header = ({isReady, headerRef, workbenchData}: HeaderProps) => {
  const [isSettingsOpen, setIsSettingsOpen] = useState(false)
  const [isDebugDialogOpen, setIsDebugDialogOpen] = useState(false)
  const settingsButtonRef = useRef<HTMLButtonElement>(null)
  const onSettingsClose = useCallback(() => setIsSettingsOpen(false), [])
  const {toggleTargetedEdits, targetedEditsEnabled} = useTargetedEditsContext()
  const {
    state: {codespaceData},
  } = useTerminalContext()

  const {
    setCreateRepositoryModelOpen,
    mobileViewActive,
    setMobileViewActive,
    previewRefreshing,
    refreshPreview,
    setWorkingMode,
    sidePanelOpen,
    toggleSidePanel,
    workingMode,
  } = useWorkbenchUI()

  const {repositoryUrl, isFetching} = workbenchData

  const nwo = useMemo(() => {
    const parts = repositoryUrl?.split('/')
    if (parts) return `${parts?.[2]} ${parts?.[3]}`
  }, [repositoryUrl])

  const handleWorkingModeChange = useCallback(
    (newModeIndex: number) => {
      const newMode = ['preview', 'code', 'split'][newModeIndex] as WorkingMode
      setWorkingMode(newMode)
    },
    [setWorkingMode],
  )

  return (
    <>
      <div ref={headerRef}>
        <div className={styles.header}>
          <div className={styles.leftSection}>
            <Stack
              direction="horizontal"
              gap="condensed"
              align="center"
              wrap="nowrap"
              className={clsx(styles.leftSectionContainer, {[styles.sidePanelOpen]: sidePanelOpen})}
            >
              <div className="d-flex flex-items-center">
                {/* GitHub logo */}
                <Link aria-label="Home" href="/">
                  <MarkGithubIcon size={32} verticalAlign="middle" className="color-fg-default" />
                </Link>
                {/* Spark switcher */}
                <div className="mx-1">
                  <SparkSwitcher />
                </div>
              </div>
              {/* Side Panel expander */}
              <div className={clsx(styles.sidePanelExpander, 'hide-sm')}>
                <IconButton
                  icon={sidePanelOpen ? SidebarCollapseIcon : SidebarExpandIcon}
                  aria-label={sidePanelOpen ? 'Collapse side panel' : 'Expand side panel'}
                  onClick={() => toggleSidePanel()}
                  className={styles.expandSidebarButton}
                />
              </div>
            </Stack>
          </div>

          <div className={styles.centerSection}>
            {/* Working mode selector */}
            <SegmentedControl
              aria-label="Working mode"
              onChange={handleWorkingModeChange}
              className={clsx(styles.workingModeSelector, 'hide-sm')}
            >
              <SegmentedControl.IconButton
                selected={workingMode === 'preview'}
                icon={BrowserIcon}
                aria-label="Preview mode"
              />
              <SegmentedControl.IconButton
                selected={workingMode === 'code'}
                icon={CodeIcon}
                aria-label="Code mode"
                className={styles.codeButton}
              />
              <SegmentedControl.IconButton
                selected={workingMode === 'split'}
                icon={SplitViewIcon}
                aria-label="Split mode"
                className="hide-sm hide-md hide-lg"
              />
            </SegmentedControl>
          </div>

          <Stack direction="horizontal" gap="condensed" align="center" justify="end" className={styles.rightSection}>
            <IconButton
              icon={TargetIcon}
              aria-label="Select element to edit"
              onClick={toggleTargetedEdits}
              className={clsx(
                styles.targetedEditsButton,
                {[styles.toggledButton]: targetedEditsEnabled},
                'hide-sm hide-md',
              )}
              inactive={!isReady || isFetching}
            />
            <IconButton
              icon={SyncIcon}
              aria-label="Refresh preview"
              onClick={refreshPreview}
              inactive={!isReady && previewRefreshing}
              className={clsx('spinHover', previewRefreshing && styles.spinOnce, 'hide-sm hide-md')}
            />
            <IconButton
              icon={DeviceMobileIcon}
              aria-label={mobileViewActive ? 'Exit mobile view' : 'Show mobile view'}
              onClick={() => setMobileViewActive(!mobileViewActive)}
              inactive={!isReady || isFetching}
              className={clsx({[styles.toggledButton]: mobileViewActive}, 'hide-sm hide-md')}
            />
            <ActionMenu>
              <ActionMenu.Anchor>
                <IconButton icon={KebabHorizontalIcon} aria-label="More actions" />
              </ActionMenu.Anchor>
              <ActionMenu.Overlay>
                <ActionList>
                  {workingMode === 'code' ? (
                    <ActionList.Item
                      aria-label="View preview"
                      onSelect={() => setWorkingMode('preview')}
                      className="hide-md hide-lg hide-xl"
                    >
                      <ActionList.LeadingVisual>
                        <BrowserIcon />
                      </ActionList.LeadingVisual>
                      View preview
                    </ActionList.Item>
                  ) : (
                    <ActionList.Item
                      aria-label="View code"
                      onSelect={() => setWorkingMode('code')}
                      className="hide-md hide-lg hide-xl"
                    >
                      <ActionList.LeadingVisual>
                        <CodeIcon />
                      </ActionList.LeadingVisual>
                      View code
                    </ActionList.Item>
                  )}
                  <ActionList.Divider className="hide-md hide-lg hide-xl" />
                  <ActionList.Item
                    aria-label="Select an element to edit"
                    className={clsx('hide-lg hide-xl', styles.targetedEditsButton)}
                    onSelect={toggleTargetedEdits}
                  >
                    <ActionList.LeadingVisual>
                      <TargetIcon />
                    </ActionList.LeadingVisual>
                    Select an element
                  </ActionList.Item>
                  <ActionList.Item
                    aria-label="Refresh preview"
                    className="hide-lg hide-xl"
                    onSelect={() => refreshPreview()}
                  >
                    <ActionList.LeadingVisual>
                      <SyncIcon />
                    </ActionList.LeadingVisual>
                    Refresh preview
                  </ActionList.Item>
                  <ActionList.Item
                    aria-label={mobileViewActive ? 'Exit mobile view' : 'Show mobile view'}
                    className="hide-sm hide-lg hide-xl"
                    onSelect={() => setMobileViewActive(!mobileViewActive)}
                  >
                    <ActionList.LeadingVisual>
                      <DeviceMobileIcon className={mobileViewActive ? 'fgColor-accent' : ''} />
                    </ActionList.LeadingVisual>
                    <span>{mobileViewActive ? 'Exit mobile view' : 'Show mobile view'}</span>
                  </ActionList.Item>
                  <ActionMenu.Divider className="hide-lg hide-xl" />
                  <OpenCodespace codespaceData={codespaceData} variant="menu" />
                  {nwo ? (
                    <ActionList.LinkItem href={repositoryUrl} target="_blank">
                      <ActionList.LeadingVisual>
                        <RepoIcon />
                      </ActionList.LeadingVisual>
                      <span className="text-normal">Go to repository</span>
                      <ActionList.Description variant="block">{nwo}</ActionList.Description>
                    </ActionList.LinkItem>
                  ) : (
                    <ActionList.Item onSelect={() => setCreateRepositoryModelOpen(true)}>
                      <ActionList.LeadingVisual>
                        <RepoPushIcon />
                      </ActionList.LeadingVisual>
                      Create repository
                    </ActionList.Item>
                  )}
                  <ActionList.Item aria-label="Settings" onSelect={() => setIsSettingsOpen(!isSettingsOpen)}>
                    <ActionList.LeadingVisual>
                      <GearIcon />
                    </ActionList.LeadingVisual>
                    Settings
                  </ActionList.Item>
                  {isFeatureEnabled('copilot_workbench_debug_panel') && (
                    <>
                      <ActionList.Divider />
                      <ActionList.Item
                        aria-label="Debug panel"
                        onSelect={() => {
                          setIsDebugDialogOpen(true)
                        }}
                      >
                        <ActionList.LeadingVisual>
                          <BugIcon />
                        </ActionList.LeadingVisual>
                        Debug panel
                        <ActionList.TrailingVisual>
                          <Label variant="attention">Staff</Label>
                        </ActionList.TrailingVisual>
                      </ActionList.Item>
                    </>
                  )}
                  <PublishDropdown variant="menu" className="hide-lg hide-xl" />
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
            {isSettingsOpen && (
              <Dialog title="Settings" onClose={onSettingsClose} position="right" returnFocusRef={settingsButtonRef}>
                <SettingsPanel
                  repositoryUrl={repositoryUrl}
                  onCreateRepository={() => setCreateRepositoryModelOpen(true)}
                />
              </Dialog>
            )}
            {isDebugDialogOpen && (
              // We lazy-load the DebugDialog to avoid loading it unnecessarily. We don't need a fallback.
              <Suspense fallback={null}>
                <DebugDialog onClose={() => setIsDebugDialogOpen(false)} />
              </Suspense>
            )}
            <PublishDropdown className="hide-sm hide-md" />
          </Stack>
        </div>
        <Banner />
      </div>

      <IconButton
        icon={SparklePencilIcon}
        aria-label="Open edit panel"
        tooltipDirection="w"
        onClick={() => workbenchData.setIsMobileSidebarOpen(true)}
        className={clsx(styles.floatingButton, 'hide-md hide-lg hide-xl')}
      />
    </>
  )
}

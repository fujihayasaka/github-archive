import {IncludeFragment} from '@github-ui/include-fragment-react'
import {usePortalTooltip} from '@github-ui/portal-tooltip/use-portal-tooltip'
import {testIdProps} from '@github-ui/test-id-props'
import {
  ArchiveIcon,
  BookIcon,
  CommentIcon,
  CopyIcon,
  DuplicateIcon,
  GearIcon,
  GraphIcon,
  type Icon,
  KebabHorizontalIcon,
  RocketIcon,
  SidebarExpandIcon,
  WorkflowIcon,
} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button, ButtonGroup, Portal} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {clsx} from 'clsx'
import {memo, type ReactNode, useCallback, useMemo, useRef, useState} from 'react'

import {
  CopyAsTemplate,
  CopyProject,
  InsightsViewOpen,
  ProjectDescriptionShow,
  ProjectDescriptionSidePanelUI,
  ProjectLinkChangelog,
  ProjectLinkDocs,
  ProjectLinkFeedback,
  ProjectTopMenuUI,
  UseThisTemplateUI,
  WorkflowsOpen,
} from '../../api/stats/contracts'
import {getInitialState} from '../../helpers/initial-state'
import {fetchJSONIslandData} from '../../helpers/json-island'
import {ViewerPrivileges} from '../../helpers/viewer-privileges'
import {usePostStats} from '../../hooks/common/use-post-stats'
import {useEnabledFeatures} from '../../hooks/use-enabled-features'
import {useSidePanel} from '../../hooks/use-side-panel'
import {Link} from '../../router'
import {useProjectRouteParams} from '../../router/use-project-route-params'
import {PROJECT_ARCHIVE_ROUTE, PROJECT_SETTINGS_ROUTE, PROJECT_WORKFLOWS_ROUTE} from '../../routes'
import {useCharts} from '../../state-providers/charts/use-charts'
import {useProjectNumber} from '../../state-providers/memex/use-project-number'
import {useProjectState} from '../../state-providers/memex/use-project-state'
import {useProjectTemplateId} from '../../state-providers/memex/use-project-template-id'
import {TopBarResources} from '../../strings'
import {PresenceAvatars} from '../presence-avatars'
import styles from './index.module.css'
import {LatestStatusUpdate} from './latest-status-update'

const InsightsNavigationButton = memo(function InsightsNavigationButton() {
  const {getChartLinkTo} = useCharts()
  const {postStats} = usePostStats()
  const postInsightsViewOpenStats = useCallback(() => {
    postStats({name: InsightsViewOpen})
  }, [postStats])
  const contentRef = useRef<HTMLAnchorElement>(null)
  const [contentProps, portalTooltip] = usePortalTooltip({
    contentRef,
    'aria-label': TopBarResources.insightsButton,
    direction: 'sw',
    anchorSide: 'outside-bottom',
  })

  return (
    <Button
      ref={contentRef}
      to={getChartLinkTo(0).url}
      onClick={postInsightsViewOpenStats}
      {...testIdProps('project-insights-button')}
      aria-label={TopBarResources.insightsButton}
      as={Link}
      className={styles.Button_1}
      {...contentProps}
    >
      <Octicon icon={GraphIcon} />
      {portalTooltip}
    </Button>
  )
})

const ProjectDetailsButton = memo(function ProjectDescriptionButton() {
  const {openPaneInfo} = useSidePanel()
  const {postStats} = usePostStats()

  const contentRef = useRef<HTMLButtonElement>(null)
  const [contentProps, portalTooltip] = usePortalTooltip({
    contentRef,
    'aria-label': TopBarResources.projectDetailsButton,
    direction: 'sw',
    anchorSide: 'outside-bottom',
  })

  return (
    <Button
      ref={contentRef}
      key="project-details-button"
      onClick={() => {
        openPaneInfo()

        postStats({
          name: ProjectDescriptionShow,
          ui: ProjectDescriptionSidePanelUI,
        })
      }}
      aria-label={TopBarResources.projectDetailsButton}
      className={styles.Button_1}
      {...testIdProps('project-memex-info-button')}
      {...contentProps}
    >
      <Octicon icon={SidebarExpandIcon} />
      {portalTooltip}
    </Button>
  )
})

const SettingsOverflowMenu = memo(function SettingsOverflowMenu() {
  const {projectNumber} = useProjectNumber()
  const {feedbackLink, copyProjectPartialUrl} = getInitialState()
  const {memex_automation_enabled} = useEnabledFeatures()
  const projectRouteParams = useProjectRouteParams()
  const [isOpen, setIsOpen] = useState(false)
  const {postStats} = usePostStats()

  const {hasWritePermissions, isLoggedIn, canCopyAsTemplate} = ViewerPrivileges()

  const toggleIsOpen = useCallback(() => {
    setIsOpen(s => !s)
  }, [])

  const openFeedback = useCallback(() => {
    toggleIsOpen()
    postStats({name: ProjectLinkFeedback, ui: ProjectTopMenuUI})
  }, [postStats, toggleIsOpen])

  const openDocs = useCallback(() => {
    toggleIsOpen()
    postStats({name: ProjectLinkDocs, ui: ProjectTopMenuUI})
  }, [postStats, toggleIsOpen])

  const openChangelog = useCallback(() => {
    toggleIsOpen()
    postStats({name: ProjectLinkChangelog, ui: ProjectTopMenuUI})
  }, [postStats, toggleIsOpen])

  const openWorkflows = useCallback(() => {
    toggleIsOpen()
    postStats({name: WorkflowsOpen})
  }, [postStats, toggleIsOpen])

  const postMakeCopyStats = useCallback(() => {
    postStats({
      name: CopyProject,
      ui: ProjectTopMenuUI,
    })
  }, [postStats])

  const postCopyAsTemplateStats = useCallback(() => {
    postStats({
      name: CopyAsTemplate,
      ui: ProjectTopMenuUI,
    })
  }, [postStats])

  const showCopyAsTemplate = isLoggedIn && canCopyAsTemplate

  const menuItems = useMemo(() => {
    const items: Array<ReactNode> = []

    if (hasWritePermissions) {
      items.push(
        memex_automation_enabled && (
          <InternalLink
            key="workflows"
            to={PROJECT_WORKFLOWS_ROUTE.generatePath(projectRouteParams)}
            icon={WorkflowIcon}
            text="Workflows"
            onClick={openWorkflows}
            testId="automation-settings-button"
          />
        ),
        <InternalLink
          key="archive"
          to={PROJECT_ARCHIVE_ROUTE.generatePath(projectRouteParams)}
          icon={ArchiveIcon}
          text="Archived items"
          onClick={toggleIsOpen}
          testId="archive-navigation-button"
        />,
        <InternalLink
          key="settings"
          to={PROJECT_SETTINGS_ROUTE.generatePath(projectRouteParams)}
          icon={GearIcon}
          text="Settings"
          onClick={toggleIsOpen}
          testId="project-settings-button"
        />,
      )
    }

    if (isLoggedIn) {
      items.push(
        <CopyDialogAction
          dialogId={`copy-project-dialog-${projectNumber}`}
          icon={CopyIcon}
          id={`topmenu-copy-project-dialog-${projectNumber}`}
          key="topMenuCopyProjectAsTemplateButton"
          onSelect={postMakeCopyStats}
          {...testIdProps('copy-project-button')}
        >
          Make a copy
        </CopyDialogAction>,
      )
    }

    if (showCopyAsTemplate) {
      items.push(
        <CopyDialogAction
          dialogId={`copy-as-template-dialog-${projectNumber}`}
          icon={DuplicateIcon}
          id={`topmenu-copy-as-template-dialog-${projectNumber}`}
          key="topMenuCopyAsTemplateButton"
          onSelect={postCopyAsTemplateStats}
          {...testIdProps('copy-as-template-button')}
        >
          Copy as template
        </CopyDialogAction>,
      )
    }

    if (items.length) {
      items.push(<ActionMenu.Divider key="divider-write-permissions" />)
    }

    const githubRuntime = fetchJSONIslandData('github-runtime') ?? 'dotcom'
    const githubVersionNumber = fetchJSONIslandData('github-version-number')
    const versionNumber = githubVersionNumber === 'unknown' ? 'latest' : githubVersionNumber
    const docsLink =
      githubRuntime === 'enterprise'
        ? `https://docs.github.com/enterprise-server@${versionNumber}/issues/planning-and-tracking-with-projects`
        : 'https://docs.github.com/issues/planning-and-tracking-with-projects'

    items.push(
      <ActionList.Group key="title-github-projects" variant="subtle">
        <ActionList.GroupHeading>GitHub Projects</ActionList.GroupHeading>
        <ExternalLink
          key="new"
          href="https://github.blog/changelog?label=projects-and-issues"
          icon={RocketIcon}
          text="What’s new"
          onClick={openChangelog}
          testId="whats-new-link"
        />
        <ExternalLink
          key="feedback"
          href={feedbackLink}
          icon={CommentIcon}
          text="Give feedback"
          onClick={openFeedback}
          testId="feedback-link"
        />
        <ExternalLink
          key="docs"
          href={docsLink}
          icon={BookIcon}
          text="GitHub Docs"
          onClick={openDocs}
          testId="docs-link"
        />
      </ActionList.Group>,
    )

    return items
  }, [
    hasWritePermissions,
    isLoggedIn,
    showCopyAsTemplate,
    openChangelog,
    feedbackLink,
    openFeedback,
    openDocs,
    memex_automation_enabled,
    openWorkflows,
    toggleIsOpen,
    projectNumber,
    postMakeCopyStats,
    postCopyAsTemplateStats,
    projectRouteParams,
  ])

  const contentRef = useRef<HTMLButtonElement>(null)
  const [contentProps, portalTooltip] = usePortalTooltip({
    contentRef,
    'aria-label': TopBarResources.viewMoreOptions,
    direction: 'sw',
    anchorSide: 'outside-bottom',
    open: isOpen ? false : undefined,
  })

  return (
    <>
      <Button
        ref={contentRef}
        {...testIdProps('project-menu-button')}
        {...contentProps}
        onClick={() => setIsOpen(s => !s)}
        aria-label={TopBarResources.viewMoreOptions}
        className={styles.Button_1}
      >
        <Octicon icon={KebabHorizontalIcon} />
        {portalTooltip}
      </Button>
      <ActionMenu anchorRef={contentRef} open={isOpen} onOpenChange={setIsOpen} key="project-menu">
        <ActionMenu.Overlay>
          <ActionList>{menuItems}</ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      <Portal>
        <div>
          {isLoggedIn && <IncludeFragment src={encodeURI(copyProjectPartialUrl)} />}
          {showCopyAsTemplate && <IncludeFragment src={encodeURI(`${copyProjectPartialUrl}?copy_as_template=true`)} />}
        </div>
      </Portal>
    </>
  )
})

const ProjectNavigationButtons = memo(function ProjectNavigationButtons({isProjectPath}: {isProjectPath: boolean}) {
  const isProjectDescriptionButtonVisible = isProjectPath

  const buttons = []
  buttons.push(<InsightsNavigationButton />)
  if (isProjectDescriptionButtonVisible) buttons.push(<ProjectDetailsButton />)
  buttons.push(<SettingsOverflowMenu />)

  return <ButtonGroup className={styles.ButtonGroup}>{buttons}</ButtonGroup>
})

// Abbreviated version of the "Make a copy" form in settings, with static defaults
const UseTemplateButton = memo(function UseTemplateButton() {
  const {copyProjectPartialUrl} = getInitialState()
  const {isLoggedIn} = ViewerPrivileges()
  const {projectNumber} = useProjectNumber()
  const {postStats} = usePostStats()
  const projectTemplateId = useProjectTemplateId()
  const postUseThisTemplateStats = useCallback(() => {
    postStats({
      name: CopyProject,
      ui: UseThisTemplateUI,
    })
  }, [postStats])

  return (
    <div {...testIdProps('use-this-template-form')} className={styles.Box}>
      <Button
        size="medium"
        variant="primary"
        {...testIdProps('use-this-template-button')}
        aria-label="Use this template"
        data-show-dialog-id={`copy-from-template-dialog-${projectNumber}`}
        onClick={postUseThisTemplateStats}
      >
        Use this template
      </Button>
      <Portal>
        <div>
          {isLoggedIn && (
            <IncludeFragment src={encodeURI(`${copyProjectPartialUrl}?template_id=${projectTemplateId}`)} />
          )}
        </div>
      </Portal>
    </div>
  )
})

type LinkProps = {
  icon: Icon
  text: string
  onClick: () => void
  testId: string
}
type InternalLinkProps = LinkProps & {to: string}
type ExternalLinkProps = LinkProps & {href: string}

const ExternalLink = ({text, icon: LinkIcon, testId, onClick, href}: ExternalLinkProps) => (
  <ActionList.LinkItem role="menuitem" href={href} target="_blank" onClick={onClick} {...testIdProps(testId)}>
    <ActionList.LeadingVisual>
      <LinkIcon />
    </ActionList.LeadingVisual>
    {text}
  </ActionList.LinkItem>
)

const InternalLink = ({text, icon: LinkIcon, testId, onClick, to}: InternalLinkProps) => (
  <ActionList.LinkItem role="menuitem" as={Link} to={to} onClick={onClick} {...testIdProps(testId)}>
    <ActionList.LeadingVisual>
      <LinkIcon />
    </ActionList.LeadingVisual>
    {text}
  </ActionList.LinkItem>
)

type CopyDialogActionProps = {
  children: React.ReactNode
  id: string
  dialogId: string
  icon: Icon
  onSelect: () => void
}

/**
 * The structure of this component addresses bug found in
 * https://github.com/github/projects-platform/issues/2797#issuecomment-2652433827
 */
const CopyDialogAction = ({children, dialogId, icon: ActionIcon, ...other}: CopyDialogActionProps) => (
  <ActionList.Item role="menuitem" onKeyPress={undefined}>
    <ActionList.LeadingVisual>
      <ActionIcon />
    </ActionList.LeadingVisual>
    <button data-show-dialog-id={dialogId} className={styles.Box_1} {...other}>
      {children}
    </button>
  </ActionList.Item>
)

export const TopBar: React.FC<{children: React.ReactNode; isProjectPath?: boolean}> = memo(function TopBar({
  children,
  isProjectPath = false,
}) {
  const {isTemplate} = useProjectState()
  const {isOrganization} = getInitialState()

  return (
    <div
      role="navigation"
      aria-label="Project"
      className={clsx(styles.topBar, {[styles.topBarWithBorder]: !isProjectPath})}
      {...testIdProps('top-bar')}
    >
      {children}
      <div style={{flex: 1}} />
      <div className={styles.topBarActions}>
        {isProjectPath && !isTemplate && <LatestStatusUpdate />}
        <PresenceAvatars />
        <ProjectNavigationButtons isProjectPath={isProjectPath} />

        {isOrganization && isTemplate ? <UseTemplateButton /> : null}
      </div>
    </div>
  )
})

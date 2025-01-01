import {testIdProps} from '@github-ui/test-id-props'
import {useTrackingRef} from '@github-ui/use-tracking-ref'
import {InfoIcon, StopIcon, XIcon} from '@primer/octicons-react'
import {Button, Flash, IconButton, Link} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {forwardRef, memo, useCallback, useEffect, useRef, useState} from 'react'

import {apiMemexWithoutLimitsBetaSignup} from './api/memex/api-post-beta-signup'
import type {BetaSignupBannerState} from './api/memex/contracts'
import {apiDismissNotice} from './api/notice/api-dismiss-notice'
import {DeletedViewToastUI} from './api/stats/contracts'
import {Board} from './components/board/board'
import {Blankslate} from './components/common/blankslate'
import {ReactTable} from './components/react_table/react-table'
import {TableColumnsProviderForTable} from './components/react_table/state-providers/table-columns/table-columns-provider-for-table'
import {IconContainer, stateColorMap, StyledToast, ToastAction, WarningIcon} from './components/toasts/toast'
import useToasts, {ToastType} from './components/toasts/use-toasts'
import {ViewNavigation} from './components/view-navigation'
import {useFieldCommands} from './features/fields/hooks/use-field-commands'
import {useHorizontalGroupCommands} from './features/grouping/hooks/use-horizontal-group-commands'
import {useSliceBy} from './features/slicing/hooks/use-slice-by'
import {useSliceByCommands} from './features/slicing/hooks/use-slice-by-commands'
import {getInitialState} from './helpers/initial-state'
import {shortcutFromEvent, SHORTCUTS} from './helpers/keyboard-shortcuts'
import {ViewType} from './helpers/view-type'
import {useSortCommands} from './hooks/command-palette/use-sort-commands'
import {usePrefixedId} from './hooks/common/use-prefixed-id'
import {useApiRequest} from './hooks/use-api-request'
import {useBindMemexToDocument} from './hooks/use-bind-memex-to-document'
import {useEnabledFeatures} from './hooks/use-enabled-features'
import {useViewType} from './hooks/use-view-type'
import {useViews} from './hooks/use-views'
import {RoadmapView} from './pages/roadmap/components/roadmap-view'
import {TableColumnsProviderForRoadmap} from './pages/roadmap/table-columns-provider-for-roadmap'
import styles from './project-view.module.css'
import {KeyPressProvider} from './state-providers/keypress/key-press-provider'
import {useMemexServiceQuery} from './state-providers/memex-service/use-memex-service-query'
import {Resources} from './strings'

export function ProjectView() {
  useBindMemexToDocument()

  const {memex_disable_autofocus} = useEnabledFeatures()

  const {data: memexServiceData} = useMemexServiceQuery()
  const betaSignupBannerState = memexServiceData?.betaSignupBanner
  const initialBetaBannerVisibility = betaSignupBannerState === 'visible' || betaSignupBannerState === 'staffship'

  const [betaBannerVisibile, setBetaBannerVisibility] = useState(initialBetaBannerVisibility)

  const viewRef = useRef<ProjectViewInnerRef>(null)
  const focusIn = useCallback(() => viewRef.current?.focusIn(), [])

  // If the user presses the down arrow before focusing anything, jump focus into the current view
  useEffect(() => {
    if (!memex_disable_autofocus) return

    const onKeyDown = (event: KeyboardEvent) => {
      if (shortcutFromEvent(event) === SHORTCUTS.ARROW_DOWN && document.activeElement === document.body) {
        event.preventDefault() // prevent scrolling down
        viewRef.current?.focusIn()
      }
    }

    document.addEventListener('keydown', onKeyDown)
    return () => document.removeEventListener('keydown', onKeyDown)
  }, [memex_disable_autofocus])

  const projectViewId = usePrefixedId('project-view')
  return (
    <div id="memex-project-view-root" {...testIdProps('app-root')} className={styles.Box}>
      <ViewNavigation projectViewId={projectViewId} onFocusIntoCurrentView={focusIn} />
      <div id={projectViewId} role="tabpanel" className={styles.Box_1}>
        {betaBannerVisibile && (
          <ProjectViewWithoutLimitsWaitlistBanner
            bannerType={betaSignupBannerState}
            setBetaBannerVisibility={setBetaBannerVisibility}
          />
        )}
        <MainView ref={viewRef} />
      </div>
    </div>
  )
}

function ProjectViewWithoutLimitsWaitlistBanner({
  setBetaBannerVisibility,
  bannerType,
}: {
  setBetaBannerVisibility: (visible: boolean) => void
  bannerType: BetaSignupBannerState | undefined
}) {
  const {addToast} = useToasts()
  const addToastRef = useTrackingRef(addToast)

  const postBetaSignup = useCallback(async () => {
    const response = await apiMemexWithoutLimitsBetaSignup()
    if (response.success) {
      setBetaBannerVisibility(false)
      addToastRef.current({
        message: Resources.betaSignupSuccessMessage,
        type: ToastType.success,
      })
    }
  }, [addToastRef, setBetaBannerVisibility])

  const dismissNotice = useCallback(async () => {
    const response = await apiDismissNotice({notice: 'memex_without_limits_beta'})
    if (response.success) {
      setBetaBannerVisibility(false)
    } else {
      addToastRef.current({
        message: Resources.dismissNoticeError,
        type: ToastType.error,
      })
    }
  }, [addToastRef, setBetaBannerVisibility])

  const {perform: join} = useApiRequest({request: postBetaSignup})
  const {perform: dismiss} = useApiRequest({request: dismissNotice})

  const onJoinWaitlist = useCallback(() => join(), [join])
  const onDismissNotice = useCallback(() => dismiss(), [dismiss])

  let testId = 'no-project-limits-waitlist-banner'
  let ctaText = Resources.joinWaitlist
  let bannerText = Resources.noProjectLimitWaitlistBanner
  const learnMoreHref = getInitialState().pwlBetaLearnMoreLink

  if (bannerType === 'staffship') {
    testId = 'no-project-limits-waitlist-staffship-banner'
    ctaText = Resources.joinBeta
    bannerText = Resources.noProjectLimitWaitlistStaffshipBanner
  }

  return (
    <Flash {...testIdProps(testId)} full className={styles.Flash_1}>
      <div className={styles.Box_2}>
        <Octicon icon={InfoIcon} />
      </div>
      <div className={styles.Box_3}>
        {bannerText} <Link href={learnMoreHref}> Learn more</Link>
      </div>
      <div className={styles.Box_4}>
        <Button tabIndex={0} onClick={onJoinWaitlist}>
          {ctaText}
        </Button>
      </div>
      <IconButton
        icon={XIcon}
        aria-label="Dismiss alert"
        variant="invisible"
        onClick={onDismissNotice}
        className={styles.IconButton}
      />
    </Flash>
  )
}

interface ProjectViewInnerProps {
  type: ViewType
}

interface ProjectViewInnerRef {
  focusIn: () => void
}

export const ProjectViewInner = forwardRef<ProjectViewInnerRef, ProjectViewInnerProps>(function ProjectViewInner(
  {type},
  ref,
) {
  switch (type) {
    case ViewType.Table:
      return (
        <KeyPressProvider>
          <TableColumnsProviderForTable>
            <ReactTable ref={ref} />
          </TableColumnsProviderForTable>
        </KeyPressProvider>
      )

    case ViewType.Roadmap:
      return (
        <KeyPressProvider>
          <TableColumnsProviderForRoadmap>
            <RoadmapView ref={ref} />
          </TableColumnsProviderForRoadmap>
        </KeyPressProvider>
      )
    case ViewType.List:
    default:
      return (
        <KeyPressProvider>
          <Board ref={ref} />
        </KeyPressProvider>
      )
  }
})

const MainView = memo(
  forwardRef<ProjectViewInnerRef>(function MainView(_, ref) {
    const {currentView, views, duplicateCurrentViewState} = useViews()
    const {
      partialFailures,
      projectLimits: {viewsLimit},
    } = getInitialState()
    const {viewType} = useViewType()
    const {addToast} = useToasts()
    const addToastRef = useTrackingRef(addToast)
    const {sliceField} = useSliceBy()

    useEffect(() => {
      const partialFailure = partialFailures?.[0]
      if (partialFailure) {
        addToastRef.current({
          message: partialFailure.message,
          type: ToastType.warning,
          keepAlive: true,
        })
      }
    }, [partialFailures, addToastRef])

    useSortCommands()
    useHorizontalGroupCommands()
    useFieldCommands()
    useSliceByCommands()

    if (!currentView) {
      return <NoViewFound />
    }

    return (
      <>
        {sliceField ? (
          <div className={styles.Box_5}>
            <div className={styles.Box_6}>
              <ProjectViewInner type={viewType} ref={ref} />
            </div>
          </div>
        ) : (
          <ProjectViewInner type={viewType} ref={ref} />
        )}
        {currentView.isDeleted ? (
          /**
           * We re-implement the toast here because we need a slightly tweaked
           * version of it, and want it to be static. We don't have a super easy
           * path to doing this re-using the definition of the Toast component currently,
           * but it might be a good place to unify these later
           */
          <StyledToast role="status" {...testIdProps('deleted-view-toast')}>
            <IconContainer sx={{bg: stateColorMap[ToastType.warning]}}>{WarningIcon}</IconContainer>
            <div className={styles.Box_7}>
              <span className={styles.Text}>This view has been deleted.</span>
              {views.length < viewsLimit ? (
                <ToastAction
                  {...testIdProps('deleted-view-toast-action')}
                  onClick={() => {
                    duplicateCurrentViewState(currentView.number, undefined, {ui: DeletedViewToastUI})
                  }}
                  className={styles.ToastAction}
                >
                  {currentView.isViewStateDirty ? 'Save a copy to make changes.' : 'Duplicate it to make changes.'}
                </ToastAction>
              ) : null}
            </div>
          </StyledToast>
        ) : null}
      </>
    )
  }),
)

const NoViewFound = memo(function NoViewFound() {
  return (
    <Blankslate data-hpc className={styles.Blankslate}>
      <Octicon icon={StopIcon} size={30} className={styles.Octicon} />
      <h2>This view no longer exists</h2>
      <p className={styles.Text_1}>Select another view to use this project.</p>
    </Blankslate>
  )
})

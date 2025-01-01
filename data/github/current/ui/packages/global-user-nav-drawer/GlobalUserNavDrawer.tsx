import {
  AlertIcon,
  BeakerIcon,
  BookIcon,
  BrowserIcon,
  CodeSquareIcon,
  CommentDiscussionIcon,
  CopilotIcon,
  GearIcon,
  GlobeIcon,
  HeartIcon,
  OrganizationIcon,
  PeopleIcon,
  PersonIcon,
  ProjectIcon,
  RepoIcon,
  SignOutIcon,
  SmileyIcon,
  StarIcon,
  UploadIcon,
  type Icon,
} from '@primer/octicons-react'
import {ActionList, Label, Spinner, Truncate} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {memo, useCallback, useEffect, useState, type ReactNode} from 'react'
import {testIdProps} from '@github-ui/test-id-props'
import {UnsafeHTMLBox} from '@github-ui/safe-html/UnsafeHTML'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {
  type ReactPartialAnchorProps,
  useExternalAnchor,
  type PropsWithPartialAnchor,
} from '@github-ui/react-core/react-partial-anchor'
import {Dialog, type DialogHeaderProps, type DialogProps} from '@primer/react/experimental'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {useClickAnalytics} from '@github-ui/use-analytics'
import {UserStatusDialog, type UserStatus} from './UserStatusDialog'
import {Emoji} from './Emoji'
import styles from './styles.module.css'
import {ErrorDialog, type ErrorDialogProps} from './ErrorDialog'
import {AccountSwitcher, type AccountSwitcherProps} from './AccountSwitcher'
import {GlobalCreateMenuItem, type GlobalCreateMenuProps} from '@github-ui/global-create-menu'
import {IncludeFragment} from '@github-ui/include-fragment-react'

import drawerStyles from './GlobalUserNavDrawer.module.css'

async function fetchLazyData(url: string): Promise<LazyLoadItemDataAttributes> {
  const response = await fetch(url)

  if (!response.ok) {
    throw new Error(`Failed to fetch data from ${url}`)
  }

  return response.json()
}

const fetchDfdTasksData = async (): Promise<LazyDfdNewTasksData> => {
  const response = await fetch('/in-product-messaging/dfd-new-tasks-indicator.json')

  if (!response.ok) {
    throw new Error('Failed to fetch DFD tasks data')
  }

  return response.json()
}

export interface GlobalUserNavDrawerProps
  extends ReactPartialAnchorProps,
    Omit<AccountSwitcherProps, 'stashedAccounts' | 'setError'> {
  owner: {
    login: string
    name: string
    avatarUrl: string
  }
  lazyLoadItemDataFetchUrl: string
  showAccountSwitcher: boolean
  showCopilot: boolean
  showEnterprises: boolean
  showEnterprise: boolean
  showGists: boolean
  showOrganizations: boolean
  showSponsors: boolean
  showUpgrade: boolean
  showFeaturesPreviews: boolean
  showEnterpriseSettings: boolean
  projectsPath: string
  gistsUrl: string
  docsUrl: string
  yourEnterpriseUrl: string
  enterpriseSettingsUrl: string
  supportUrl: string
  onClose: DialogProps['onClose']
  createMenuProps: GlobalCreateMenuProps
}

type LazyDfdNewTasksData = {
  /**
   * Whether to render the experiment at all
   *
   * `false`: the page will render completely normally
   *
   * `true`: we will track the A/B impression and render one of the variants
   */
  enableDfdNewTasksExperiment: boolean

  /**
   * `-1`: not rendering the experiment
   *
   * `0`: rendering the control variant showing the normal experience (albeit tracking it)
   *
   * `1`: showing the New Tasks Button in the NavDrawer
   */
  showDfdNewTasksVariant: -1 | 0 | 1
}

export type LazyLoadItemDataAttributes = {
  userStatus: UserStatus
  enterpriseTrialUrl?: string
  hasUnseenFeatures: boolean
  stashedAccounts: AccountSwitcherProps['stashedAccounts']
}

type LazyLoadItemData = {fetchError: boolean} & LazyLoadItemDataAttributes

const erroredLazyLoadItemData: LazyLoadItemData = {
  fetchError: true,
  userStatus: {},
  hasUnseenFeatures: false,
  stashedAccounts: [],
}

type UserStatusItemProps = {
  lazyLoadItemData: LazyLoadItemData | null
  onClick: () => void
}

function NavLink({
  href,
  icon,
  analyticsCategory = 'Global navigation',
  analyticsAction,
  analyticsLabel,
  children,
  extraOnClick,
}: {
  href: string
  icon: Icon
  analyticsCategory?: string
  analyticsAction: string
  analyticsLabel?: string
  children: ReactNode

  /** click handler to fire in addition to the automatic analytics event built into NavLink */
  extraOnClick?: () => void
}) {
  const {sendClickAnalyticsEvent} = useClickAnalytics()
  const onClick = useCallback(() => {
    sendClickAnalyticsEvent({
      category: analyticsCategory,
      action: analyticsAction,
      label: analyticsLabel,
    })

    extraOnClick?.()
  }, [sendClickAnalyticsEvent, extraOnClick, analyticsCategory, analyticsAction, analyticsLabel])

  return (
    <ActionList.LinkItem href={href} onClick={onClick}>
      <ActionList.LeadingVisual>
        <Octicon icon={icon} />
      </ActionList.LeadingVisual>
      {children}
    </ActionList.LinkItem>
  )
}

const UserStatusNavItem = memo(function UserStatusNavItem({lazyLoadItemData, onClick}: UserStatusItemProps) {
  return (
    <ActionList.Item {...testIdProps('global-user-nav-set-status-item')} onSelect={onClick}>
      <ActionList.LeadingVisual>
        {lazyLoadItemData?.userStatus?.emojiAttributes ? (
          <Emoji {...lazyLoadItemData?.userStatus.emojiAttributes} />
        ) : (
          <Octicon icon={SmileyIcon} />
        )}
      </ActionList.LeadingVisual>
      {lazyLoadItemData ? (
        <UnsafeHTMLBox
          className={styles.emojiContainer}
          html={lazyLoadItemData.userStatus.messageHtml || 'Set status'}
        />
      ) : (
        <LoadingSkeleton height="md" />
      )}
    </ActionList.Item>
  )
})

type UpgradeNavItemProps = {
  lazyLoadItemData: LazyLoadItemData | null
}

function UpgradeNavItem(props: UpgradeNavItemProps) {
  const enterpriseTrialUrl = props.lazyLoadItemData?.enterpriseTrialUrl
  if (enterpriseTrialUrl) {
    return (
      <NavLink
        href={enterpriseTrialUrl}
        icon={UploadIcon}
        analyticsCategory="start_a_free_trial"
        analyticsAction="click_to_set_up_enterprise_trial"
        analyticsLabel="ref_loc:side_panel;ref_cta:try_enterprise"
      >
        Try Enterprise
        {/* eslint-disable-next-line primer-react/direct-slot-children */}
        <ActionList.TrailingVisual>
          <Label variant="primary">Free</Label>
        </ActionList.TrailingVisual>
      </NavLink>
    )
  } else {
    return (
      <NavLink href="/account/choose?action=upgrade" icon={UploadIcon} analyticsAction="UPGRADE_PLAN">
        Upgrade
      </NavLink>
    )
  }
}

function FeaturePreviewDialog({onClose, login}: {onClose: () => void; login: string}) {
  return (
    <Dialog
      title="Feature preview dialog"
      onClose={onClose}
      renderBody={() => {
        return (
          <Dialog.Body className="p-0">
            <IncludeFragment src={`/users/${login}/feature_previews`}>
              <p className="text-center mt-3" data-hide-on-error>
                <Spinner />
              </p>
              <p className="flash flash-error mb-0 mt-2" data-show-on-error hidden>
                <AlertIcon />
                Sorry, something went wrong and we were not able to fetch the feature previews
              </p>
            </IncludeFragment>
          </Dialog.Body>
        )
      }}
      className={drawerStyles.Dialog}
    />
  )
}

/* This component will eventually use the Dialog component from Primer React to encapsulate the entire global user
 * nav drawer. We aren't able to manage the dialog here because the user nav drawer opens several constituent dialogs -
 * the user status dialog and the feature preview dialog - which are currently rendered in Rails-land using the Primer
 * Dialog component from primer_view_components. It's architected this way because dialogs from the two frameworks
 * have proven to be somewhat incompatible. For example, pressing 'esc' closes the nav drawer instead of the user
 * status dialog, etc. Keeping all the actual dialogs in Rails sidesteps these issues. When the constituent dialogs
 * are eventually ported to React, we can stick a Dialog in here and manage the entire nav drawer in React.
 *
 * We've actually tried this already. See
 * https://github.com/github/github/blob/35187c0a5d3277413a0bb74db33c521462787ada/ui/packages/global-user-nav-drawer/GlobalUserNavDrawer.tsx
 * for inspiration when it's time to move the dialog into this component.
 */
function GlobalUserNavDrawerDialog(props: GlobalUserNavDrawerProps & {onClose: DialogProps['onClose']}) {
  const [lazyLoadItemData, setLazyLoadItemData] = useState<LazyLoadItemData | null>(null)
  const [lazyDfdNewTasksData, setLazyDfdNewTasksData] = useState<LazyDfdNewTasksData | null>(null)
  const [showUserStatusDialog, setShowUserStatusDialog] = useState(false)
  const [showFeaturePreviewDialog, setShowFeaturePreviewDialog] = useState(false)
  const {onClose, owner} = props
  const profilePath = `/${owner.login}`
  const {sendClickAnalyticsEvent} = useClickAnalytics()

  const openUserStatusDialog = useCallback(() => {
    setShowUserStatusDialog(true)
    sendClickAnalyticsEvent({category: 'Global navigation', action: 'USER_STATUS'})
  }, [sendClickAnalyticsEvent])

  const onUserStatusClosed = useCallback(
    async (statusPromise?: Promise<UserStatus> | string) => {
      setShowUserStatusDialog(false)

      if (statusPromise && typeof statusPromise !== 'string' && lazyLoadItemData) {
        try {
          const userStatus = await statusPromise
          setLazyLoadItemData({...lazyLoadItemData, userStatus})
        } catch {
          // Do nothing
        }
      }
    },
    [lazyLoadItemData],
  )
  const openFeaturePreviewDialog = useCallback(() => {
    setShowFeaturePreviewDialog(true)
    sendClickAnalyticsEvent({category: 'Global navigation', action: 'FEATURE_PREVIEW'})
  }, [sendClickAnalyticsEvent])

  useEffect(() => {
    if (!lazyLoadItemData) {
      const fetchData = async () => {
        try {
          const lazyItemData = await fetchLazyData(props.lazyLoadItemDataFetchUrl)

          setLazyLoadItemData(prevVal => ({
            ...(prevVal || {}),
            fetchError: false,
            ...lazyItemData,
          }))
        } catch {
          setLazyLoadItemData(erroredLazyLoadItemData)
        }
      }

      fetchData()
    }
  }, [props.lazyLoadItemDataFetchUrl, lazyLoadItemData])

  useEffect(() => {
    const fetchDfdTasks = async () => {
      try {
        const dfdTasksData = await fetchDfdTasksData()
        setLazyDfdNewTasksData(dfdTasksData)
      } catch {
        // Do nothing
      }
    }

    fetchDfdTasks()
  }, [])

  const renderHeader = useCallback(
    ({dialogLabelId}: DialogHeaderProps) => {
      return (
        <div
          className="d-flex pr-3 pl-3 pt-3"
          id={dialogLabelId}
          aria-label="User navigation"
          role="heading"
          aria-level={1}
        >
          <div className="d-flex flex-1">
            <div className="d-flex">
              <GitHubAvatar src={owner.avatarUrl} size={32} />
              <div className="lh-condensed overflow-hidden d-flex flex-column flex-justify-center ml-2 f5 mr-auto">
                <div className="text-bold">
                  <Truncate title={owner.login} maxWidth={175}>
                    {owner.login}
                  </Truncate>
                </div>
                <div className="fgColor-muted">
                  <Truncate title={owner.name} maxWidth={175}>
                    {owner.name}
                  </Truncate>
                </div>
              </div>
            </div>
          </div>
          {props.showAccountSwitcher && (
            <AccountSwitcher
              canAddAccount={props.canAddAccount}
              addAccountPath={props.addAccountPath}
              switchAccountPath={props.switchAccountPath}
              stashedAccounts={lazyLoadItemData?.stashedAccounts ?? null}
              loginAccountPath={props.loginAccountPath}
              setError={setError}
            />
          )}
          <Dialog.CloseButton onClose={() => onClose('close-button')} />
        </div>
      )
    },
    [
      onClose,
      owner,
      lazyLoadItemData?.stashedAccounts,
      props.canAddAccount,
      props.addAccountPath,
      props.switchAccountPath,
      props.loginAccountPath,
      props.showAccountSwitcher,
    ],
  )

  const [error, setError] = useState<ErrorDialogProps | false>(false)

  return error ? (
    <ErrorDialog {...error} onClose={() => setError(false)} />
  ) : (
    <Dialog onClose={props.onClose} width="medium" position="right" renderHeader={renderHeader}>
      {showUserStatusDialog && <UserStatusDialog onClose={onUserStatusClosed} />}
      {showFeaturePreviewDialog && (
        <FeaturePreviewDialog onClose={() => setShowFeaturePreviewDialog(false)} login={props.owner.login} />
      )}
      <ActionList variant="full">
        <UserStatusNavItem lazyLoadItemData={lazyLoadItemData} onClick={openUserStatusDialog} />

        <ActionList.Divider />

        <NavLink href={profilePath} icon={PersonIcon} analyticsAction="PROFILE">
          Your profile
        </NavLink>
        <NavLink href={`${profilePath}?tab=repositories`} icon={RepoIcon} analyticsAction="YOUR_REPOSITORIES">
          Your repositories
        </NavLink>
        {props.showCopilot && (
          <NavLink
            href="/settings/copilot"
            icon={CopilotIcon}
            analyticsCategory="try_copilot"
            analyticsAction="click_to_try_copilot"
            analyticsLabel="ref_loc:side_panel;ref_cta:your_copilot"
          >
            Your Copilot
          </NavLink>
        )}
        <NavLink href={props.projectsPath} icon={ProjectIcon} analyticsAction="YOUR_PROJECTS">
          Your projects
        </NavLink>
        <NavLink href={`${profilePath}?tab=stars`} icon={StarIcon} analyticsAction="YOUR_STARS">
          Your stars
        </NavLink>
        {props.showGists && (
          <NavLink href={props.gistsUrl} icon={CodeSquareIcon} analyticsAction="YOUR_GISTS">
            Your gists
          </NavLink>
        )}
        {props.showOrganizations && (
          <NavLink href="/settings/organizations" icon={OrganizationIcon} analyticsAction="YOUR_ORGANIZATIONS">
            Your organizations
          </NavLink>
        )}
        {props.showEnterprises && (
          <NavLink
            href="/settings/enterprises"
            icon={GlobeIcon}
            analyticsCategory="enterprises_more_discoverable"
            analyticsAction="click_your_enterprises"
            analyticsLabel="ref_loc:side_panel;ref_cta:your_enterprises;is_navigation_redesign:true"
            extraOnClick={() => {
              // Piggy back onto the NavLinks onClick, so that clicking either the visual button or just clicking the
              // NavLink normally will result in a Nudge analytics event in addition to the standard Nav analytics event
              if (
                lazyDfdNewTasksData?.enableDfdNewTasksExperiment &&
                lazyDfdNewTasksData?.showDfdNewTasksVariant === 1
              ) {
                sendClickAnalyticsEvent({
                  location: 'global_user_nav_drawer',
                  category: 'dfd_nav_new_tasks_nudge_1',
                  action: 'new_task',
                  tag: 'a',
                  group: 'engage',
                })
              }
            }}
          >
            Your enterprises
            {lazyDfdNewTasksData?.enableDfdNewTasksExperiment && lazyDfdNewTasksData?.showDfdNewTasksVariant === 0 && (
              <span data-analytics-visible='{"category":"dfd_nav_new_tasks_nudge_0","action":"visible","group":"engage"}' />
            )}
            {lazyDfdNewTasksData?.enableDfdNewTasksExperiment && lazyDfdNewTasksData?.showDfdNewTasksVariant === 1 && (
              /* eslint-disable-next-line primer-react/direct-slot-children */
              <ActionList.TrailingVisual>
                <span data-analytics-visible='{"category":"dfd_nav_new_tasks_nudge_1","action":"visible","group":"engage"}' />

                <Label variant="done">New task</Label>
              </ActionList.TrailingVisual>
            )}
          </NavLink>
        )}
        {props.showEnterprise && (
          <NavLink href={props.yourEnterpriseUrl} icon={GlobeIcon} analyticsAction="YOUR_ENTERPRISE">
            Your enterprise
          </NavLink>
        )}
        {props.showSponsors && (
          <NavLink href="/sponsors/accounts" icon={HeartIcon} analyticsAction="SPONSORS">
            Your sponsors
          </NavLink>
        )}

        <ActionList.Divider />

        <GlobalCreateMenuItem {...props.createMenuProps} />

        {props.showUpgrade && <UpgradeNavItem lazyLoadItemData={lazyLoadItemData} />}

        {props.showFeaturesPreviews && (
          <ActionList.Item onSelect={openFeaturePreviewDialog}>
            <ActionList.LeadingVisual>
              <Octicon icon={BeakerIcon} />
            </ActionList.LeadingVisual>
            {lazyLoadItemData?.hasUnseenFeatures && (
              <ActionList.TrailingVisual>
                <Label variant="accent">New</Label>
              </ActionList.TrailingVisual>
            )}
            <span>Feature preview</span>
          </ActionList.Item>
        )}

        <NavLink href="/settings/profile" icon={GearIcon} analyticsAction="SETTINGS">
          Settings
        </NavLink>
        {props.showEnterpriseSettings && (
          <NavLink href={props.enterpriseSettingsUrl} icon={GlobeIcon} analyticsAction="ENTERPRISE_SETTINGS">
            Enterprise settings
          </NavLink>
        )}

        <ActionList.Divider />
        <NavLink href="https://github.com/home" icon={BrowserIcon} analyticsAction="MARKETINGWEBSITE">
          GitHub Website
        </NavLink>
        <NavLink href={props.docsUrl} icon={BookIcon} analyticsAction="DOCS">
          GitHub Docs
        </NavLink>
        <NavLink href={props.supportUrl} icon={PeopleIcon} analyticsAction="SUPPORT">
          GitHub Support
        </NavLink>
        <NavLink href="https://community.github.com" icon={CommentDiscussionIcon} analyticsAction="COMMUNITY">
          GitHub Community
        </NavLink>

        <ActionList.Divider />

        <NavLink href="/logout" icon={SignOutIcon} analyticsAction="LOGOUT">
          Sign out
        </NavLink>
      </ActionList>
    </Dialog>
  )
}

function ExternallyAnchoredGlobalUserNavDrawer(props: PropsWithPartialAnchor<GlobalUserNavDrawerProps>) {
  const {open, setOpen, ref: anchorRef} = useExternalAnchor(props.reactPartialAnchor)
  const onClose = useCallback(() => {
    setOpen(false)
    setTimeout(() => {
      // Dialog will soon support `returnFocusRef`, which should be used instead
      anchorRef.current?.focus()
    })
  }, [setOpen, anchorRef])

  if (open) {
    return <GlobalUserNavDrawerDialog {...props} onClose={onClose} />
  }

  return <></>
}

export function GlobalUserNavDrawer(props: GlobalUserNavDrawerProps) {
  if (props.reactPartialAnchor) {
    return <ExternallyAnchoredGlobalUserNavDrawer {...props} reactPartialAnchor={props.reactPartialAnchor} />
  }

  // If no anchor is provided, assume the drawer state is externally controlled
  return <GlobalUserNavDrawerDialog {...props} />
}

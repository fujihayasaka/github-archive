import {IssueBodyLoading} from '@github-ui/issue-body/IssueBodyLoading'

import type {OptionConfig} from '@github-ui/issue-create/OptionConfig'
import {getSafeConfig} from '@github-ui/issue-create/OptionConfig'
import {CreateIssueEntry, type CreateIssuePropsEntry} from '@github-ui/issue-create/CreateIssueDialogEntry'
import {getIssueCreateArguments, type IssueCreateMetadataTypes} from '@github-ui/issue-create/TemplateArgs'
import type {OnCreateProps} from '@github-ui/issue-create/Model'

import {issuePath, userHovercardPath} from '@github-ui/paths'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {useNavigate} from '@github-ui/use-navigate'
import {Heading, Link} from '@primer/react'
import {Suspense, useCallback, useEffect, useMemo} from 'react'
import type {PreloadedQuery, UseQueryLoaderLoadQueryOptions} from 'react-relay'

import type {AppPayload} from '../../types/app-payload'
import {explodeIssueNewPathToRepositoryData, getCurrentRepoIssuesUrl, isNewIssuePathForRepo} from '../../utils/urls'

import type {RepositoryPickerCurrentRepoQuery} from '@github-ui/item-picker/RepositoryPickerCurrentRepoQuery.graphql'
import {LABELS} from '../../constants/labels'
import {VALUES} from '../../constants/values'
import {VIEW_IDS} from '../../constants/view-constants'
import {useQueryContext} from '../../contexts/QueryContext'
import {noop} from '@github-ui/noop'
import {GitHubAvatar} from '@github-ui/github-avatar'
import styles from './IssueCreatePane.module.css'

export type IssueCreatePaneProps = {
  currentRepoQueryRef?: PreloadedQuery<RepositoryPickerCurrentRepoQuery> | undefined | null
  loadCurrentRepo?: (
    variables: RepositoryPickerCurrentRepoQuery['variables'],
    options?: UseQueryLoaderLoadQueryOptions,
  ) => void
  disposeCurrentRepo?: () => void
  initialMetadataValues?: IssueCreateMetadataTypes
}

export const IssueCreatePane = ({
  currentRepoQueryRef,
  loadCurrentRepo,
  disposeCurrentRepo,
  initialMetadataValues,
}: IssueCreatePaneProps) => {
  const appPayload = useAppPayload<AppPayload>()
  const storageKeyPrefix = VALUES.storageKeyPrefix(appPayload)
  const navigate = useNavigate()
  const {activeSearchQuery, setCurrentViewId} = useQueryContext()
  const pasteUrlsAsPlainText = appPayload?.paste_url_link_as_plain_text || false
  const useMonospaceFont = appPayload?.current_user_settings?.use_monospace_font || false
  const emojiSkinTonePreference = appPayload?.current_user_settings?.preferred_emoji_skin_tone
  const singleKeyShortcutsEnabled = appPayload?.current_user_settings?.use_single_key_shortcut || false

  const {search, pathname} = ssrSafeLocation
  const {scoped_repository: scoped_repository_from_payload, current_user} = appPayload
  const {avatarUrl, login} = current_user

  // This is a workaround to soft navigations where we can go from not having a scoped repo in issues#index to the issue#viewer
  // where we now have a scoped repo, which would not detect the scoped repo change given the payload isn't refreshed on soft nav.
  // Therefore we first attempt to parse a scoped repo from the pathname, which will only have a potentially valid value on soft nav,
  // otherwise we fallback to the payload value.
  const urlScopedRepository = useMemo(() => explodeIssueNewPathToRepositoryData(pathname), [pathname])
  const scoped_repository = urlScopedRepository ?? scoped_repository_from_payload

  const urlSearchParams = new URLSearchParams(search)
  const issueCreateArguments = getIssueCreateArguments(urlSearchParams, initialMetadataValues)

  const argRepository = issueCreateArguments?.repository?.name
  const argOwner = issueCreateArguments?.repository?.owner

  const prefillRepository = useMemo(() => {
    if (scoped_repository) {
      // If we're scoped to a given repository, we use that to prefill
      return {
        owner: scoped_repository.owner,
        name: scoped_repository.name,
      }
    } else if (argRepository && argOwner) {
      // If we're given a repository in dashboard scope, we use that to prefill
      return {
        owner: argOwner,
        name: argRepository,
      }
    }
  }, [scoped_repository, argRepository, argOwner])

  useEffect(() => {
    if (prefillRepository)
      loadCurrentRepo?.({...prefillRepository, includeTemplates: true}, {fetchPolicy: 'store-or-network'})

    return () => disposeCurrentRepo && disposeCurrentRepo()
  }, [disposeCurrentRepo, prefillRepository, loadCurrentRepo])

  const onCancel = useCallback(() => {
    const path = isNewIssuePathForRepo(pathname)
      ? getCurrentRepoIssuesUrl({query: activeSearchQuery})
      : '/issues/assigned'
    navigate(path)
  }, [activeSearchQuery, navigate, pathname])

  const optionConfig: OptionConfig = {
    storageKeyPrefix,
    singleKeyShortcutsEnabled,
    pasteUrlsAsPlainText,
    useMonospaceFont,
    emojiSkinTonePreference,
    issueCreateArguments,
    insidePortal: false,
    scopedRepository: scoped_repository,
  }

  const navigateToIssue = ({issue}: Pick<OnCreateProps, 'issue'>) => {
    navigate(
      issuePath({
        owner: issue.repository.owner.login,
        repo: issue.repository.name,
        issueNumber: issue.number,
      }),
    )
  }

  const createIssueProps: CreateIssuePropsEntry = {
    onCreateSuccess: ({issue, createMore}: OnCreateProps) => {
      if (createMore) {
        return
      }
      setCurrentViewId(VIEW_IDS.repository)
      navigateToIssue({issue})
    },
    onCreateError: noop,
    onCancel,
    navigate,
  }
  const safeConfig = getSafeConfig(optionConfig)

  return (
    <div className={styles.createPane}>
      <Link href={`/${login}`} className={styles.avatarLink}>
        <span className="sr-only">{LABELS.viewProfile(login)}</span>
        <GitHubAvatar
          src={avatarUrl}
          size={32}
          alt={''}
          data-hovercard-url={userHovercardPath({owner: login})}
          className={styles.avatar}
        />
      </Link>
      <div className={styles.createPaneContainer} data-testid="issue-create-pane-container">
        <Heading as="h1" className={styles.header}>
          {LABELS.issueCreatePaneTitle}
        </Heading>
        <Suspense fallback={<IssueBodyLoading />}>
          {currentRepoQueryRef && (
            <CreateIssueEntry
              currentRepoQueryRef={currentRepoQueryRef}
              config={safeConfig}
              createIssueProps={createIssueProps}
              renderWithoutDialog
            />
          )}
        </Suspense>
      </div>
    </div>
  )
}

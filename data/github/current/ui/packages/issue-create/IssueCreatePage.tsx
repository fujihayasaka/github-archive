import {useUser} from '@github-ui/use-user'
import {RepositoryFragment, type Repository} from '@github-ui/item-picker/RepositoryPicker'
import type {RepositoryPickerRepository$key} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import {Box, Heading, Link} from '@primer/react'
import {useCallback, useEffect, useRef} from 'react'
import {ssrSafeLocation} from '@github-ui/ssr-utils'

import {useFragment} from 'react-relay'
import {graphql, readInlineData} from 'relay-runtime'
import {CreateIssueFooter} from './CreateIssueFooter'
import {CreateIssueForm} from './CreateIssueForm'
import type {FetchedIssueCreatePayload, OnCreateProps} from './utils/model'
import {type OptionConfig, type SafeOptionConfig, getSafeConfig} from './utils/option-config'
import {type IssueCreateMetadataTypes, getIssueCreateArguments} from './utils/template-args'
import type {IssueCreatePage$key} from './__generated__/IssueCreatePage.graphql'
import {getSelectedTemplate, useHandleTemplateChange} from './use-handle-template-change'
import {useNavigate, useSearchParams} from '@github-ui/use-navigate'
import {LABELS} from './constants/labels'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {issuePath, repositoryPath, userHovercardPath} from '@github-ui/paths'
import styles from './IssueCreatePage.module.css'
import {useIssueCreateConfigContext} from './contexts/IssueCreateConfigContext'
import {useIssueCreateDataContext} from './contexts/IssueCreateDataContext'
import type {IssueFormRef} from '@github-ui/issue-form/Types'
import {noop} from '@github-ui/noop'
import {useSafeClose} from './hooks/use-safe-close'

import {IssueCreateContextProvider} from './contexts/IssueCreateContext'
import {useIssueCreateInitialValuesContext} from './contexts/IssueCreateInitialValuesContext'
import {DifferentTemplateLink} from './DifferentTemplateLink'

export type IssueCreatePageProps = {
  initialMetadataValues: IssueCreateMetadataTypes
  currentRepository: IssueCreatePage$key
  storageKeyPrefix: string
  pasteUrlsAsPlainText: boolean
  useMonospaceFont: boolean
  emojiSkinTonePreference: number | undefined
  singleKeyShortcutsEnabled: boolean
}

export const IssueCreatePage = ({
  initialMetadataValues,
  currentRepository,
  storageKeyPrefix,
  pasteUrlsAsPlainText,
  useMonospaceFont,
  emojiSkinTonePreference,
  singleKeyShortcutsEnabled,
}: IssueCreatePageProps) => {
  const data = useFragment(
    graphql`
      fragment IssueCreatePage on Repository
      @argumentDefinitions(
        templateFilter: {type: "String!", defaultValue: ""}
        withTemplate: {type: "Boolean!", defaultValue: false}
      ) {
        ...RepositoryPickerRepository
        name
        owner {
          login
        }
        hasAnyTemplates
        ...useHandleTemplateChange @arguments(filename: $templateFilter) @include(if: $withTemplate)
      }
    `,
    currentRepository,
  )
  const [urlSearchParams] = useSearchParams()
  const withTemplates = !!urlSearchParams.get('template')

  // eslint-disable-next-line no-restricted-syntax
  const repository = readInlineData<RepositoryPickerRepository$key>(RepositoryFragment, data)

  const {currentUser} = useUser()

  const initialContextValues = useIssueCreateInitialValuesContext()
  const issueCreateArguments = getIssueCreateArguments(urlSearchParams, initialMetadataValues, initialContextValues)

  const optionConfig: OptionConfig = {
    storageKeyPrefix,
    singleKeyShortcutsEnabled,
    pasteUrlsAsPlainText,
    useMonospaceFont,
    emojiSkinTonePreference,
    issueCreateArguments: {
      ...issueCreateArguments,
      repository: {
        owner: data.owner.login,
        name: data.name,
      },
    },
    insidePortal: false,
  }
  const safeConfig = getSafeConfig(optionConfig)
  const template = withTemplates ? getSelectedTemplate(data) : undefined

  const preselectedData = {
    repository,
    template,
  }
  const issueFormRef = useRef<IssueFormRef>(null)

  if (!currentUser) {
    reportError(
      new Error(`Could not find the current user when loading IssueCreatePage for ${ssrSafeLocation?.href.toString()}`),
    )
    return <div>Current user not found</div>
  }
  const {avatarUrl, login} = currentUser

  return (
    <IssueCreateContextProvider optionConfig={safeConfig} preselectedData={preselectedData}>
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
          <div
            style={{
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'flexStart',
              marginBottom: template ? 4 : 12,
              position: 'relative',
              top: template ? '-10px' : 0,
            }}
          >
            <Heading as="h2" sx={{fontSize: 2}} id="issue-create-pane-title">
              {LABELS.issueCreateDialogTitleTemplatePane}
            </Heading>
            {data.hasAnyTemplates && (
              <DifferentTemplateLink
                nameWithOwner={repository.nameWithOwner}
                templateName={template?.name}
                issueFormRef={issueFormRef}
              />
            )}
          </div>

          <Box sx={{display: 'flex', flexDirection: 'column', alignItems: 'stretch', gap: 2}} tabIndex={-1}>
            <IssueCreatePageInternal
              template={template}
              repository={repository}
              optionConfig={safeConfig}
              issueFormRef={issueFormRef}
            />
          </Box>
        </div>
      </div>
    </IssueCreateContextProvider>
  )
}

type IssueCreatePageInternalProps = {
  template: FetchedIssueCreatePayload | undefined
  repository: Repository
  issueFormRef: React.RefObject<IssueFormRef>

  optionConfig: SafeOptionConfig
}

const IssueCreatePageInternal = ({template, issueFormRef, repository, optionConfig}: IssueCreatePageInternalProps) => {
  const defaultNavigate = useNavigate()
  const navigate = optionConfig.navigate || defaultNavigate
  const {setDisplayMode, setCreateMoreCreatedPath} = useIssueCreateConfigContext()
  const {title, setTitle, body, setBody, resetTitleAndBody, clearMetadata, clearSessionData, usedStorageKeyPrefix} =
    useIssueCreateDataContext()

  const handleTemplateChange = useHandleTemplateChange({
    optionConfig,
    repository,
    navigate,
    setDisplayMode,
  })

  const onCreateSuccess = useCallback(
    ({issue, createMore}: OnCreateProps) => {
      clearSessionData()
      // clear all data from issue form elements
      issueFormRef.current?.clearSessionStorage()
      if (createMore) {
        // We're re-rendering the same compoent and this ensures that data will start to be saved in localStorage
        if (template) {
          issueFormRef.current?.resetInputs()
          handleTemplateChange(template)
        } else {
          clearMetadata()
          resetTitleAndBody()
        }
        return
      }
      navigate(
        issuePath({
          owner: issue.repository.owner.login,
          repo: issue.repository.name,
          issueNumber: issue.number,
        }),
      )
    },
    [clearMetadata, clearSessionData, handleTemplateChange, issueFormRef, navigate, resetTitleAndBody, template],
  )

  const {onSafeClose: onCancel} = useSafeClose({
    storageKeyPrefix: usedStorageKeyPrefix || '',
    issueFormRef,
    onCancel: () => {
      navigate(
        repositoryPath({
          owner: repository.owner.login,
          repo: repository.name,
          action: 'issues',
        }),
      )
    },
  })

  useEffect(() => {
    setCreateMoreCreatedPath({
      owner: repository.owner.login,
      repo: repository.name,
      number: undefined,
    })
  }, [repository, setCreateMoreCreatedPath])

  return (
    <CreateIssueForm
      issueFormRef={issueFormRef}
      onCreateSuccess={onCreateSuccess}
      onCreateError={noop}
      onCancel={onCancel}
      selectedTemplate={template}
      repository={repository}
      title={title}
      setTitle={setTitle}
      body={body}
      setBody={setBody}
      resetTitleAndBody={resetTitleAndBody}
      clearOnCreate={clearSessionData}
      focusTitleInput
      footer={<CreateIssueFooter onClose={onCancel} />}
    />
  )
}

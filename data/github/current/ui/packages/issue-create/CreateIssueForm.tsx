import {validateIssueBody, validateIssueTitle} from '@github-ui/entity-validators'
// eslint-disable-next-line no-restricted-imports
import {reportError} from '@github-ui/failbot'
import type {RepositoryPickerRepository$data as Repository} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import type {ProjectPickerProject$data as Project} from '@github-ui/item-picker/ProjectPickerProject.graphql'
import {CommentBox, type CommentBoxConfig, type ViewMode} from '@github-ui/comment-box/CommentBox'
import type {Subject} from '@github-ui/comment-box/subject'
import type {SafeHTMLString} from '@github-ui/safe-html'

import {Box, Dialog, Flash} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {type FormEvent, type RefObject, useEffect, useId, useImperativeHandle, useMemo, useRef, useState} from 'react'
import {useRelayEnvironment} from 'react-relay'
import type {Environment} from 'relay-runtime'

import {ERRORS} from './constants/errors'
import {LABELS} from './constants/labels'
import type {CreateIssueInput} from './mutations/__generated__/createIssueMutation.graphql'
import {commitCreateIssueMutation} from './mutations/create-issue-mutation'
import {IssueCreationKind, instanceOfIssueFormData, type IssueCreatePayload, type OnCreateProps} from './utils/model'
import {IssueFormElements} from '@github-ui/issue-form/IssueFormElements'
import type {IssueFormElementRef, IssueFormRef} from '@github-ui/issue-form/Types'
import {AlertIcon, LinkExternalIcon} from '@primer/octicons-react'
import {useIssueCreateConfigContext} from './contexts/IssueCreateConfigContext'
import {ContributorFooter} from '@github-ui/contributor-footer/ContributorFooter'
import {getPotentialFormDefaultValuesFromUrl} from './utils/urls'
import {useAnalytics} from '@github-ui/use-analytics'
import {useIssueCreateDataContext} from './contexts/IssueCreateDataContext'
import {MetadataSelectors} from './metadata/MetadataSelectors'
import {commitUpdateIssueProjectsMutation} from '@github-ui/item-picker/updateIssueProjectsMutation'
import {CreateIssueFormTitle} from './CreateIssueFormTitle'
import styles from './CreateIssueForm.module.css'
import {AriaAlert, Banner} from '@primer/react/experimental'
import {useNavigate} from '@github-ui/use-navigate'
import {MarkdownEditor} from '@github-ui/markdown-editor'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {UserRestrictedView} from './UserRestrictedView'

export type CreateIssueCallbackProps = {
  onCreateSuccess: ({issue, createMore}: OnCreateProps) => void
  onCreateError: (error: Error) => void
  onCancel: () => void
  onBeforeCreate?: (issueBody: string) => Promise<string>
}

export type CreateIssueFormProps = {
  repository: Repository
  selectedTemplate?: IssueCreatePayload
  title: string
  setTitle: (title: string) => void
  body: string
  setBody: (body: string) => void
  clearOnCreate: () => void
  focusTitleInput?: boolean
  footer?: JSX.Element
  issueFormRef: RefObject<IssueFormRef>
  showUserRestrictedView?: boolean
} & CreateIssueCallbackProps

export const CreateIssueForm = ({
  repository,
  title,
  setTitle,
  body,
  setBody,
  clearOnCreate,
  onCreateSuccess,
  onCreateError,
  selectedTemplate,
  footer,
  issueFormRef,
  onBeforeCreate,
  showUserRestrictedView = false,
}: CreateIssueFormProps): JSX.Element => {
  const {
    optionConfig,
    createMore,
    createMoreCreatedPath,
    setCreateMoreCreatedPath,
    isSubmitting,
    setIsSubmitting,
    onCreateAction,
    setIsFileUploading,
  } = useIssueCreateConfigContext()
  const showMetadataSidepanel = !optionConfig.insidePortal
  const titleInputRef = useRef<HTMLInputElement>(null)

  const [viewMode, setViewMode] = useState<ViewMode>('edit')
  const [titleValidationResult, setTitleValidationResult] = useState<string | undefined>(undefined)
  const [bodyValidationResult, setBodyValidationResult] = useState<string | undefined>(undefined)
  const [submissionErrors, setSubmissionErrors] = useState<string | null>(null)

  const errorBanner = useRef<HTMLDivElement>(null)

  const environment = useRelayEnvironment()
  const {sendAnalyticsEvent} = useAnalytics()
  const {labels, assignees, projects, milestone, issueType, parentIssue, usedStorageKeyPrefix} =
    useIssueCreateDataContext()

  const commentBoxConfig: CommentBoxConfig = {
    pasteUrlsAsPlainText: optionConfig.pasteUrlsAsPlainText,
    useMonospaceFont: optionConfig.useMonospaceFont,
    emojiSkinTonePreference: optionConfig.emojiSkinTonePreference,
  }

  const restrictedViewContent = (
    <UserRestrictedView
      reasonHTML={repository.viewerInteractionLimitReasonHTML as SafeHTMLString}
      issuesUrl={`/${repository.owner.login}/${repository.name}/issues`}
    />
  )

  const canIssueType = repository.viewerIssueCreationPermissions.typeable

  const formatFormErrorMessage = (errors: Error[]) => {
    const errorMessages = errors
      .map(err => err?.message)
      .filter(Boolean)
      .join(', ')

    // Some gql errors start with lowercase letters, so normalizing it
    const cleanedErrorMessages = errorMessages ? errorMessages.charAt(0).toUpperCase() + errorMessages.slice(1) : null

    return cleanedErrorMessages ?? ERRORS.createIssueError
  }

  useEffect(() => {
    if (submissionErrors && submissionErrors.length > 0 && errorBanner?.current) {
      errorBanner.current.focus()
    }
  }, [errorBanner, submissionErrors])

  useImperativeHandle(
    onCreateAction,
    () => ({
      onCreate: async (isSubmittingArg, createMoreArg) => {
        if (isSubmittingArg) return

        let refToFocusOnError: HTMLInputElement | IssueFormElementRef | undefined = undefined

        const inputValidationResult = validateIssueTitle(title)
        setTitleValidationResult(inputValidationResult.errorMessage)
        if (!inputValidationResult.isValid && titleInputRef.current) {
          refToFocusOnError = titleInputRef.current
        }

        const isIssueForm = selectedTemplate && instanceOfIssueFormData(selectedTemplate.data)
        let issueBodyToSave = body
        if (isIssueForm && issueFormRef.current) {
          const invalidInputs = issueFormRef.current.getInvalidInputs()
          // If there are validation errors, use first input if there's no ref yet
          if (invalidInputs.length > 0) {
            refToFocusOnError = refToFocusOnError || invalidInputs[0]
          } else {
            issueBodyToSave = issueFormRef.current.markdown() ?? ''
          }
        }

        // We validate the length === 0 also for the initial state, in which the validation result will be undefined, too.
        if (
          refToFocusOnError ||
          titleValidationResult !== undefined ||
          (title ?? '').trim().length === 0 ||
          repository === undefined ||
          bodyValidationResult !== undefined
        ) {
          // If there is an input with an error, focus it
          refToFocusOnError?.focus()
          return
        }

        setSubmissionErrors(null)
        setIsSubmitting(true)

        if (onBeforeCreate) {
          issueBodyToSave = await onBeforeCreate(issueBodyToSave)
        }

        let issueTemplate = undefined
        if (
          selectedTemplate &&
          (selectedTemplate.kind === IssueCreationKind.IssueTemplate ||
            selectedTemplate.kind === IssueCreationKind.IssueForm)
        ) {
          issueTemplate = selectedTemplate.name
        }

        const input: CreateIssueInput = {
          repositoryId: repository.id,
          title: title ? title.trim() : '',
          body: issueBodyToSave,
          labelIds: labels.length > 0 ? labels.map(label => label.id) : undefined,
          assigneeIds: assignees.length > 0 ? assignees.map(assignee => assignee.id) : undefined,
          milestoneId: milestone?.id,
          issueTypeId: canIssueType || issueTemplate ? issueType?.id : null,
          issueTemplate,
          parentIssueId: parentIssue ? parentIssue.id : null,
        }

        commitCreateIssueMutation({
          environment,
          input,
          onError: (error: Error) => {
            reportError(formatError(error.message))
            onCreateError(error)
            setIsSubmitting(false)

            let errorMessage = ERRORS.createIssueError

            if (error.cause && Array.isArray(error.cause) && error.cause.length > 0) {
              errorMessage = formatFormErrorMessage(error.cause)
            }

            setSubmissionErrors(errorMessage)
          },
          onCompleted: response => {
            setIsSubmitting(false)
            if (!response.createIssue?.issue) {
              response.createIssue?.errors.map(e => reportError(formatError(e.message)))

              let errorMessage = ERRORS.createIssueError
              if (response.createIssue?.errors && response.createIssue?.errors.length > 0) {
                errorMessage = formatFormErrorMessage(response.createIssue.errors as Error[])
              }

              setSubmissionErrors(errorMessage)
              return
            }

            const newIssue = response.createIssue.issue

            sendAnalyticsEvent('analytics.click', 'ISSUE_CREATE_NEW_ISSUE_BUTTON', {
              issueId: newIssue.id,
              issueNumber: newIssue.number,
              issueNWO: `${newIssue.repository.owner.login}/${newIssue.repository.name}`,
            })

            if (projects.length > 0) {
              assignIssueToProjects(newIssue.id, projects, environment)
            }

            if (createMoreArg) {
              setViewMode('edit')
              setCreateMoreCreatedPath({...createMoreCreatedPath, number: newIssue.number})
            } else {
              clearOnCreate()
            }

            onCreateSuccess({issue: newIssue, createMore: createMoreArg})
          },
        })
      },
    }),
    [
      title,
      selectedTemplate,
      body,
      issueFormRef,
      titleValidationResult,
      repository,
      bodyValidationResult,
      setIsSubmitting,
      labels,
      assignees,
      milestone?.id,
      canIssueType,
      issueType?.id,
      parentIssue,
      environment,
      onCreateError,
      sendAnalyticsEvent,
      projects,
      onCreateSuccess,
      setCreateMoreCreatedPath,
      createMoreCreatedPath,
      clearOnCreate,
      onBeforeCreate,
    ],
  )

  const handleTitleChange = (e: FormEvent<HTMLInputElement>) => {
    const inputTitle = e.currentTarget.value
    validateAndSetTitle(inputTitle)
  }

  const validateAndSetTitle = (newTitle: string) => {
    const inputValidationResult = validateIssueTitle(newTitle)
    // when title changes, check if we need to clear validation error
    // validation error are only added when user tries to create the issue
    if (inputValidationResult.isValid) {
      setTitleValidationResult(undefined)
    }
    setTitle(newTitle)
  }
  const handleBodyChange = (inputBody: string) => {
    validateAndSetBody(inputBody)
  }
  const validateAndSetBody = (newBody: string) => {
    const inputValidationResult = validateIssueBody(newBody)

    setBodyValidationResult(inputValidationResult.errorMessage)
    setBody(newBody)
  }

  const isIssueForm = selectedTemplate && instanceOfIssueFormData(selectedTemplate.data)

  const subject = useMemo<Subject | undefined>(() => {
    if (repository) {
      return {
        type: 'issue',
        repository: {
          databaseId: repository.databaseId!,
          nwo: `${repository.owner.login}/${repository.name}`,
          slashCommandsEnabled: repository.slashCommandsEnabled,
        },
      }
    }
  }, [repository])

  const validationErrorId = useId()

  const footerButtons = []
  const navigate = useNavigate()
  const copilotCTARef = useRef<HTMLButtonElement>(null)
  const [isCopilotCTADialogOpen, setIsCopilotCTADialogOpen] = useState(false)
  const navigateToCopilot = () => {
    sendAnalyticsEvent('analytics.click', 'ISSUE_CREATE_NEW_ISSUE_WITH_COPILOT_BUTTON', {
      repoNWO: `${repository.owner.login}/${repository.name}`,
    })
    navigate(`/copilot?prompt=Create an issue in ${repository.nameWithOwner} to`)
  }
  if (
    isFeatureEnabled('copilot_immersive_issue_creation_cta') &&
    optionConfig.copilotShowFunctionality &&
    (repository.visibility !== 'PUBLIC' || repository.viewerCanPush) &&
    (!selectedTemplate || selectedTemplate.kind === IssueCreationKind.BlankIssue)
  ) {
    footerButtons.push(
      <MarkdownEditor.FooterButton
        ref={copilotCTARef}
        key="create-issue-with-copilot"
        variant="invisible"
        leadingVisual={LinkExternalIcon}
        size="small"
        className={styles.footerButton}
        onClick={() => {
          if (body.length || title.length) {
            setIsCopilotCTADialogOpen(true)
          } else {
            navigateToCopilot()
          }
        }}
      >
        {LABELS.copilotCTAButton}
      </MarkdownEditor.FooterButton>,
    )
  }

  const mainContent = showUserRestrictedView ? (
    restrictedViewContent
  ) : (
    <>
      {isCopilotCTADialogOpen && (
        <Dialog
          title={LABELS.copilotCTADialogTitle}
          onClose={() => setIsCopilotCTADialogOpen(false)}
          footerButtons={[
            {
              buttonType: 'default',
              content: LABELS.copilotCTADialogCancelButton,
              onClick: () => setIsCopilotCTADialogOpen(false),
            },
            {
              buttonType: 'primary',
              content: LABELS.copilotCTADialogContinueButton,
              onClick: navigateToCopilot,
            },
          ]}
          returnFocusRef={copilotCTARef}
        >
          {LABELS.copilotCTADialogDescription}
        </Dialog>
      )}
      {submissionErrors && (
        <Banner
          ref={errorBanner}
          title="Error"
          description={<AriaAlert>{submissionErrors}</AriaAlert>}
          variant="critical"
          className={styles.errorBanner}
          role="alert"
        />
      )}
      <CreateIssueFormTitle
        title={title}
        titleInputRef={titleInputRef}
        handleTitleChange={handleTitleChange}
        titleValidationResult={titleValidationResult}
        emojiTone={optionConfig.emojiSkinTonePreference}
      />
      {subject && !isIssueForm && (
        <div className={styles.commentBox}>
          <CommentBox
            subject={subject}
            label={LABELS.issueCreateBodyLabel}
            showLabel
            placeholder={LABELS.issueBodyPlaceholder}
            viewMode={viewMode}
            onChangeViewMode={setViewMode}
            value={body as SafeHTMLString}
            onSave={() => onCreateAction?.current?.onCreate(isSubmitting, createMore)}
            onChange={handleBodyChange}
            saveButtonTrailingIcon={false}
            userSettings={commentBoxConfig}
            minHeightLines={optionConfig.insidePortal ? 14 : 20}
            aria-describedby={bodyValidationResult ? validationErrorId : undefined}
            setIsFileUploading={setIsFileUploading}
            footerButtons={footerButtons}
          />
          {bodyValidationResult && (
            <Flash variant="danger" id={validationErrorId}>
              <Octicon icon={AlertIcon} />
              {bodyValidationResult}
            </Flash>
          )}
        </div>
      )}
      {subject && isIssueForm && instanceOfIssueFormData(selectedTemplate.data) && (
        <IssueFormElements
          outputRef={issueFormRef}
          issueFormRef={selectedTemplate.data}
          subject={subject}
          commentBoxConfig={commentBoxConfig}
          sessionStorageKey={usedStorageKeyPrefix}
          defaultValuesById={getPotentialFormDefaultValuesFromUrl()}
          onSave={() => onCreateAction?.current?.onCreate(isSubmitting, createMore)}
          setIsFileUploading={setIsFileUploading}
        />
      )}
    </>
  )

  const metadataContent = (
    <>
      <MetadataSelectors />
      <ContributorFooter
        supportFileUrl={repository.supportFileUrl ?? undefined}
        codeOfConductFileUrl={repository.codeOfConductFileUrl ?? undefined}
        securityPolicyUrl={repository.securityPolicyUrl ?? undefined}
        contributingFileUrl={repository.contributingFileUrl ?? undefined}
      />
    </>
  )

  const footerContent = showUserRestrictedView ? null : (
    <>{footer && <Box sx={{gridArea: 'footer', mt: [4, 4, isIssueForm ? 2 : 0]}}>{footer}</Box>}</>
  )

  if (showMetadataSidepanel) {
    return (
      <Box sx={{display: 'flex', flexDirection: 'row', flexWrap: 'wrap', gap: 4}}>
        <Box
          className="width-fit"
          sx={{
            display: ['flex', 'flex', 'grid', 'grid'],
            gridTemplateColumns: ['auto', 'auto', 'minmax(0, 1fr) 256px', 'minmax(0, 1fr) 296px'],
            flexDirection: 'column',
            gridTemplateAreas: `
              "body metadata"
              "footer nil"
            `,
            flexGrow: 1,
            columnGap: 4,
            rowGap: 0,
          }}
        >
          <Box sx={{gridArea: 'body', display: 'flex', flexDirection: 'column', gap: 3}}>{mainContent}</Box>
          <Box sx={{display: 'flex', flexDirection: 'column', gridArea: 'metadata'}}>{metadataContent}</Box>
          {footerContent}
        </Box>
      </Box>
    )
  } else {
    return (
      <>
        {mainContent}
        {metadataContent}
        {footerContent}
      </>
    )
  }
}

function assignIssueToProjects(issueId: string, projects: Project[], environment: Environment) {
  for (const project of projects) {
    commitUpdateIssueProjectsMutation({environment, issueId, projectId: project.id})
  }
}

function formatError(message: string) {
  return new Error(`Issue create mutation failed with error: ${message}`)
}

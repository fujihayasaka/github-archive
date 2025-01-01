import type {SaveResponse, SaveResponseErrorDetails} from '@github-ui/code-view-types'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {resetMemoizeFetchJSON} from '@github-ui/use-latest-commit'
import {useNavigate} from '@github-ui/use-navigate'
import {verifiedFetch} from '@github-ui/verified-fetch'
import type {WebCommitDialogState} from '@github-ui/web-commit-dialog'
import {Suspense, lazy, useState} from 'react'
import {useLocation} from 'react-router-dom'
import {usePromptsBanner} from '../contexts/PromptBannersContext'
import {isPromptComparePage, promptToYaml, type PromptConfig} from '../prompts'
import type {PromptAppPayload} from '../types'
import {pollUntilCommitHasQuorum} from '../utils/commits'
import {useModels} from '../contexts/ModelsContext'

// Lazy load as WebCommitDialog is not compatible with SSR
const WebCommitDialog = lazy(async () => {
  const module = await import('@github-ui/web-commit-dialog')
  return {default: module.WebCommitDialog}
})

interface SaveBlobData {
  message: string
  placeholder_message: string
  description: string
  author_email?: string
  'commit-choice'?: string
  target_branch?: string
  quick_pull: string
  guidance_task: string
  commit: string
  same_repo?: number
  pr: string
}

interface EditSaveBlobData extends SaveBlobData {
  content_changed: boolean
  filename: string
  new_filename: string
  value: string
  redirect_to: string
}

function defaultCommitMessage({
  isNewPrompt,
  promptName,
  promptPath,
}: {
  isNewPrompt: boolean
  promptName?: string | undefined
  promptPath?: string | undefined
}) {
  const verb = isNewPrompt ? 'Create' : 'Update'
  const promptFileName = promptPath?.split('/').pop()
  return `${verb} ${promptName || promptFileName || 'prompt'}`
}

export default function PromptWebCommitDialog({
  dialogState,
  setDialogState,
  activePrompt,
}: {
  dialogState: WebCommitDialogState
  setDialogState: (state: WebCommitDialogState) => void
  activePrompt: PromptConfig
}) {
  const {payload} = useAppPayload<PromptAppPayload>()
  const {setBanner} = usePromptsBanner()

  const location = useLocation()
  const isNewPrompt = location.pathname.includes('models/prompt/new') ? true : false

  const models = useModels()

  const {
    repository,
    commitInfo: {webCommitInfo, refInfo, fileSaveAuthenticityToken},
  } = payload

  const {
    authorEmails,
    defaultEmail,
    canCommitStatus,
    forkedRepo,
    defaultNewBranchName,
    repoHeadEmpty,
    commitOid,
    pr,
    saveUrl,
  } = webCommitInfo

  const ownerName = repository.ownerLogin
  const refName = refInfo.name
  const placeholderMessage = defaultCommitMessage({
    isNewPrompt,
    promptName: activePrompt.name,
    promptPath: activePrompt.path,
  })
  const quickPullChoice = !forkedRepo && !repoHeadEmpty

  const [dialogMessage, setDialogMessage] = useState<string>(placeholderMessage)
  const [description, setDescription] = useState<string>('')
  const [isQuickPull, setIsQuickPull] = useState<boolean>(canCommitStatus !== 'allowed' || !!forkedRepo)
  const [prTargetBranch, setPRTargetBranch] = useState<string>(defaultNewBranchName)
  const [errorMessage, setErrorMessage] = useState<string>('')
  const [errorDetails, setErrorDetails] = useState<SaveResponseErrorDetails>()
  const [authorEmail, setAuthorEmail] = useState(authorEmails?.length ? defaultEmail : undefined)
  const navigate = useNavigate()
  const isComparePage = isPromptComparePage(location.pathname)

  const onSave = async () => {
    setDialogState('saving')

    const quickPullBase = forkedRepo ? `${ownerName}:${refName}` : refName
    const fileName = activePrompt.path

    const sharedData: SaveBlobData = {
      message: dialogMessage,
      placeholder_message: placeholderMessage,
      description,
      author_email: authorEmail ?? undefined,
      'commit-choice': quickPullChoice ? (isQuickPull ? 'quick-pull' : 'direct') : undefined,
      target_branch: quickPullChoice ? (isQuickPull ? prTargetBranch : refName) : undefined,
      quick_pull: isQuickPull ? quickPullBase : '',
      guidance_task: '',
      commit: commitOid || '',
      same_repo: !forkedRepo && !repoHeadEmpty ? 1 : undefined,
      pr: pr ?? '',
    }

    const data: EditSaveBlobData = {
      ...sharedData,
      content_changed: true,
      filename: fileName || '',
      new_filename: fileName || '',
      value: promptToYaml(activePrompt, models),
      redirect_to: isComparePage ? 'models_compare_page' : 'models_repo_page',
    }

    const formData = new FormData()
    for (const [key, dataValue] of Object.entries(data)) {
      if (dataValue !== undefined) {
        formData.set(key, dataValue)
      }
    }

    //  We are making a call to blob_controller#save.
    //  Normally, verifiedFetch sets the 'GitHub-Verified-Fetch': 'true' header
    //  which is sufficient to verify that the call is coming from a verified source,
    //  but because blob_controller does not include ApplicationController::VerifiedFetchDependency
    //  we need to explicitly pass in an authenticity token
    // eslint-disable-next-line github/authenticity-token
    formData.append('authenticity_token', fileSaveAuthenticityToken ?? '')

    try {
      const result = await verifiedFetch(saveUrl, {
        method: 'post',
        body: formData,
        headers: {Accept: 'application/json'},
      })

      const json: SaveResponse = await result.json()

      if (json.data.commitQuorumPollPath) {
        await pollUntilCommitHasQuorum(json.data.commitQuorumPollPath)
      }

      // on a successful save, we are redirected back to the prompt page
      if (json.data.redirect) {
        const redirectUrl = json.data.redirect
        const url = redirectUrl.startsWith(window.location.origin)
          ? redirectUrl.replace(window.location.origin, '')
          : redirectUrl

        // Reset the latest commit cache so that the next time the user navigates to the blob, they see the latest commit
        resetMemoizeFetchJSON()

        if (json.data.message) {
          setBanner({message: json.data.message, variant: 'info'})
        } else {
          setBanner({message: 'Prompt successfully committed.', variant: 'success'})
        }
        setDialogState('saved')
        // sometimes react will not have updated the dialog state before the redirect happens
        // so we need to wait a bit for the state to update before redirecting
        setTimeout(() => {
          navigate(url, {reloadDocument: true})
        }, 50)

        return
      } else if (json.data.error && json.data.secretBypassMetadata) {
        setDialogState('closed')
      } else if (json.data.error) {
        setDialogState('pending')
        setErrorMessage(json.data.error)
        if (json.data.error_details) {
          setErrorDetails(json.data.error_details)
        }
      } else {
        setErrorMessage('File could not be edited')
        setDialogState('pending')
      }
    } catch {
      setErrorMessage('File could not be edited')
      setDialogState('pending')
    }
  }

  return (
    <Suspense fallback={null}>
      <WebCommitDialog
        message={dialogMessage}
        setMessage={setDialogMessage}
        description={description}
        setDescription={setDescription}
        isQuickPull={isQuickPull}
        setIsQuickPull={setIsQuickPull}
        prTargetBranch={prTargetBranch}
        setPRTargetBranch={setPRTargetBranch}
        errorMessage={errorMessage}
        errorDetails={errorDetails}
        dialogState={dialogState}
        setDialogState={setDialogState}
        setAuthorEmail={setAuthorEmail}
        onSave={onSave}
        refName={refName}
        webCommitInfo={webCommitInfo}
        helpUrl="https://docs.github.com/en/github/collaborating-with-issues-and-pull-requests/committing-changes-to-your-project"
      />
    </Suspense>
  )
}

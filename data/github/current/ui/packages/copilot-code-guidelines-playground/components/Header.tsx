import {ERRORS} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {CopilotChatMessageStreamer} from '@github-ui/copilot-chat/utils/copilot-chat-message-streamer'
import {testIdProps} from '@github-ui/test-id-props'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {ArrowLeftIcon, PlayIcon} from '@primer/octicons-react'
import {Button, IconButton, Label} from '@primer/react'
import {SampleCodeStatus, usePlaygroundContext, type CodeComment} from '../PlaygroundContext'

export interface HeaderProps {
  playgroundRunsPath: string
}

interface CommentReference {
  type: string
  data: {
    body: string
    line: number
  }
}

interface ReviewAgentResponse {
  copilot_references: CommentReference[]
  type: undefined
}

export default function Header({playgroundRunsPath}: HeaderProps) {
  const {
    sampleCode,
    sampleCodeStatus,
    setCodeComments,
    setSampleCodeStatus,
    setErrorMessage,
    saveCodeGuideline,
    currentCodingGuideline,
    indexPath,
    isSaving,
  } = usePlaygroundContext()
  const headerTitle = currentCodingGuideline.id ? 'Edit coding guideline' : 'New coding guideline'

  return (
    <div className="d-flex flex-items-left flex-md-items-center flex-justify-between gap-3 flex-column flex-sm-row">
      <div className="d-flex flex-items-center gap-1">
        <IconButton
          as="a"
          icon={ArrowLeftIcon}
          aria-label="Back to coding guidelines"
          size="small"
          variant="invisible"
          href={indexPath}
        />
        <h1 className="text-semibold h2">{headerTitle}</h1>
        <Label variant="success" className="ml-1 mt-1">
          Preview
        </Label>
      </div>

      <div className="d-flex gap-2">
        <Button
          leadingVisual={PlayIcon}
          onClick={RunSample}
          // TODO: Uncomment once we allow more samples
          // count={numberOfSamples > 1 ? numberOfSamples : undefined}
          disabled={sampleCode === null}
          loading={sampleCodeStatus === SampleCodeStatus.Loading}
          loadingAnnouncement="Generating code review comments"
          {...testIdProps('run-samples-button')}
        >
          Run
          {/* TODO: Uncomment once we allow more samples */}
          {/* {numberOfSamples > 1 && ' all'} */}
        </Button>
        <Button variant="primary" loading={isSaving} loadingAnnouncement="Saving guideline" onClick={saveCodeGuideline}>
          Save guideline
        </Button>
      </div>
    </div>
  )

  async function RunSample() {
    setSampleCodeStatus(SampleCodeStatus.Loading)
    setErrorMessage(null)

    try {
      const comments = await generateComments()
      setCodeComments(comments)
    } catch {
      handleRunSampleError()
    }

    setSampleCodeStatus(SampleCodeStatus.Loaded)
  }

  async function generateComments() {
    const dotcomBody = {
      playground: {
        sample_code: sampleCode,
        description: currentCodingGuideline.description,
      },
    }

    const dotcomRes = await verifiedFetchJSON(playgroundRunsPath, {body: dotcomBody, method: 'POST'})

    if (!dotcomRes.ok) {
      const error = (await dotcomRes.json()).error
      handleRunSampleError(error)
      return []
    }

    const {references, integration, token, api} = await dotcomRes.json()

    const capiHeaders = {
      Authorization: `GitHub-Bearer ${token}`,
      'copilot-integration-id': integration,
      'X-Copilot-Code-Review-Mode': 'eval',
      'Content-Type': 'text/event-stream',
    }

    const capiBody = {
      messages: [
        {
          role: 'user',
          copilot_references: references,
        },
      ],
    }

    const capiRes = await fetch(`${api}/agents/github-code-review`, {
      method: 'POST',
      mode: 'cors',
      cache: 'no-cache',
      headers: capiHeaders,
      body: JSON.stringify(capiBody),
    })

    if (!capiRes.ok) {
      handleRunSampleError(ERRORS[capiRes.status])
      return []
    }

    const reader = capiRes.body?.getReader()
    if (!reader) throw Error('No reader found in response body')

    const streamer = new CopilotChatMessageStreamer<ReviewAgentResponse>(reader)
    const messages: ReviewAgentResponse[] = []
    for await (const message of streamer.stream()) {
      messages.push(message)
    }

    if (messages.length === 0) {
      return []
    }

    // The agent should only be returning one message
    const refs = messages[0]?.copilot_references || []

    return extractAndFormatReferences(refs)
  }

  function extractAndFormatReferences(refs: CommentReference[]): CodeComment[] {
    return refs.reduce((arr: CodeComment[], ref) => {
      if (ref.type === 'github.generated-pull-request-comment') {
        const details = ref.data?.body
        const lineNumber = ref.data?.line

        if (details && lineNumber) arr.push({details, lineNumber})
      }

      return arr
    }, [])
  }

  function handleRunSampleError(error?: string) {
    setErrorMessage(error || 'Something went wrong while running this guideline')
  }
}

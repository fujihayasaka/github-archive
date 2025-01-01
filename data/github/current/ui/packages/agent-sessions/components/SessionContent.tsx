import {MarkdownRenderer} from '@github-ui/copilot-markdown'
import {ActionList, ActionMenu, IconButton, Stack, Link} from '@primer/react'
import {useMemo} from 'react'
import type {LogEntry, Choice} from '../types/session'
import {getReadableSessionState} from '../types/session'
import SessionElapsedTime from './SessionElapsedTime'
import {useLogs, type UseSessionLogsProps} from '../hooks/useLogs'
import {useSyncFavicon} from '../hooks/useSyncFavicon'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {Banner} from '@primer/react/experimental'
import {Tool, ToolPrimaryContent, ToolRenderer} from './tool/Tool'
import {KebabHorizontalIcon, InfoIcon} from '@primer/octicons-react'
import {useSessionContext} from '../contexts/SessionContext'
import {useCurrentRepository} from '@github-ui/current-repository'
import {SessionStopButton} from './SessionStopButton'
import {SessionFailedBanner} from './SessionFailedBanner'
import {generateWorkflowRunLink} from '../utils/generate-actions-link'
import {BootingUpMessage, LoadingMessage} from './LoadingMessage'
import merge from 'lodash.merge'

interface SessionContentProps extends UseSessionLogsProps {}

export function SessionContent({useMockData, logsPollingInterval}: SessionContentProps) {
  const {session} = useSessionContext()
  const {ownerLogin, name: repoName} = useCurrentRepository()

  const {
    data: logsData,
    isLoading: logsIsLoading,
    showPollingError,
  } = useLogs({
    useMockData,
    logsPollingInterval,
  })
  useSyncFavicon(session.state)

  // Memoize the processing of tool result IDs to avoid recalculating on every render
  const toolResultIds = useMemo(() => {
    const resultIds = new Set<string>()
    if (logsData) {
      for (const logEntry of logsData) {
        for (const choice of logEntry.choices) {
          const tool = choice.delta.tool_calls?.[0]
          const isToolResult = !!tool && 'content' in choice.delta

          if (isToolResult && tool.id) {
            resultIds.add(tool.id)
          }
        }
      }
    }
    return resultIds
  }, [logsData]) // Only recalculate when logsData changes

  const dedupedLogsData = useMemo(() => {
    const idToLogEntry = new Map<string, LogEntry>()
    if (logsData) {
      for (const logEntry of logsData) {
        let newEntry = logEntry
        const existingEntry = idToLogEntry.get(logEntry.id)
        // If we already know about a logEntry with that ID, combine the log entries
        if (existingEntry) {
          newEntry = Object.assign({}, existingEntry, logEntry)
          const finalChoices = new Array<Choice>()
          const idToChoiceWithTool = new Map<string, Choice>()
          // Combine choices with the same tool ID
          for (const choice of logEntry.choices.concat(existingEntry.choices)) {
            // Explicit assumption there will only be one tool call in a choice
            const tool = choice.delta.tool_calls?.[0]
            // Choices without tool calls are always unique
            if (!tool || !tool.id) {
              finalChoices.push(choice)
              continue
            }
            let newChoice = choice
            const existingChoice = idToChoiceWithTool.get(tool.id)
            if (existingChoice) {
              newChoice = merge({}, existingChoice, choice)
            }
            idToChoiceWithTool.set(tool.id, newChoice)
          }
          newEntry.choices = finalChoices.concat(Array.from(idToChoiceWithTool.values()))
        }
        idToLogEntry.set(logEntry.id, newEntry)
      }
    }
    return [...idToLogEntry.entries()]
  }, [logsData])

  const osweFixEnabled = useFeatureFlag('copilot_coding_agent_fix_oswe')

  return (
    <div>
      <SessionHeader />
      <Stack direction="vertical" padding={'spacious'} className={'border border-top-0 bgColor-inset rounded-bottom-2'}>
        {logsIsLoading && !showPollingError && <LoadingMessage message="Loading…" />}
        {!logsIsLoading && !showPollingError && logsData?.length === 0 && session.state !== 'in_progress' && (
          <div>No logs to display</div>
        )}
        {!logsIsLoading && logsData && logsData?.length > 0 && (
          <>
            {osweFixEnabled
              ? dedupedLogsData?.map(([id, entry]) => {
                  return <LogEntry key={`entry-${id}`} {...entry} toolResultIds={toolResultIds} />
                })
              : logsData?.map((entry, i) => {
                  // eslint-disable-next-line @eslint-react/no-array-index-key
                  return <LogEntry key={`entry-${i}`} {...entry} toolResultIds={toolResultIds} />
                })}
          </>
        )}
        {showPollingError && (
          <Banner
            aria-label="Error with hidden title"
            title="Error"
            hideTitle
            description="There was an error loading the logs. Please try again later."
            variant="critical"
            primaryAction={(() => {
              const workflowLink = session.workflow_run_id
                ? generateWorkflowRunLink(ownerLogin, repoName, session.workflow_run_id)
                : undefined

              return workflowLink ? (
                <Banner.PrimaryAction as="a" href={workflowLink}>
                  View detailed logs
                </Banner.PrimaryAction>
              ) : undefined
            })()}
          />
        )}
        {session.state === 'in_progress' && !logsIsLoading && !showPollingError && (
          <>
            {logsData && logsData.length > 0 ? <LoadingMessage message="Copilot is working…" /> : <BootingUpMessage />}
          </>
        )}
        {session.state === 'failed' && !showPollingError && (
          <SessionFailedBanner errorMessage={session.error?.message ?? null} workflowRunId={session.workflow_run_id} />
        )}
      </Stack>
    </div>
  )
}

function SessionHeader() {
  const {
    session: {
      state,
      created_at: createdAt,
      completed_at: completedAt,
      workflow_run_id,
      premium_requests: premiumRequests,
    },
  } = useSessionContext()
  const {ownerLogin, name: repoName} = useCurrentRepository()
  const premiumRequestsEnabled = useFeatureFlag('copilot_coding_agent_premium_requests')

  const workflowLink = generateWorkflowRunLink(ownerLogin, repoName, workflow_run_id)

  return (
    <div className="position-sm-sticky top-0 pt-2 bgColor-default" style={{zIndex: 1}}>
      <Stack
        direction={'horizontal'}
        gap={'spacious'}
        wrap="wrap"
        className={'px-4 py-3 border rounded-2 rounded-bottom-0'}
      >
        <Stack gap="condensed">
          <span className="text-small fgColor-muted">Status</span>
          <span className="text-capitalize h4 text-semibold">{getReadableSessionState(state)}</span>
        </Stack>
        <Stack gap="condensed">
          <span className="text-small fgColor-muted">Duration</span>
          <span role="timer" className="text-semibold h4">
            <SessionElapsedTime createdAt={createdAt} completedAt={completedAt} state={state} />
          </span>
        </Stack>
        {premiumRequestsEnabled && (
          <Stack gap="condensed">
            <span className="text-small fgColor-muted">Premium Requests</span>
            <Stack direction="horizontal">
              <span className="text-capitalize h4 text-semibold">{premiumRequests}</span>
              <Link
                href="https://docs.github.com/copilot/managing-copilot/monitoring-usage-and-entitlements/about-premium-requests"
                title="Learn more about premium requests"
                inline
                muted
              >
                <InfoIcon className="v-align-middle" />
              </Link>
            </Stack>
          </Stack>
        )}
        {workflowLink && (
          <div className="flex-1 d-flex flex-justify-end">
            <SessionStopButton />
            <ActionMenu>
              <ActionMenu.Anchor>
                <IconButton icon={KebabHorizontalIcon} aria-label="Open menu" />
              </ActionMenu.Anchor>
              <ActionMenu.Overlay>
                <ActionList>
                  <ActionList.LinkItem href={workflowLink}>View verbose logs</ActionList.LinkItem>
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
          </div>
        )}
      </Stack>
    </div>
  )
}

interface LogEntryProps extends LogEntry {
  toolResultIds: Set<string>
}

function LogEntry({choices, toolResultIds}: LogEntryProps) {
  return (
    <>
      {choices.map((choice, i) => (
        // eslint-disable-next-line @eslint-react/no-array-index-key
        <LogEntryChoice key={`choice-${i}`} choice={choice} toolResultIds={toolResultIds} />
      ))}
    </>
  )
}

type LogEntryChoiceProps = {
  choice: Choice
  toolResultIds: Set<string>
}

function LogEntryChoice({choice, toolResultIds}: LogEntryChoiceProps) {
  const osweFixEnabled = useFeatureFlag('copilot_coding_agent_fix_oswe')
  if (!osweFixEnabled) {
    return <LogEntryChoiceDeprecated choice={choice} toolResultIds={toolResultIds} />
  }

  const tool = choice.delta.tool_calls?.[0]

  if (!tool && choice.delta.content && choice.delta.role === 'assistant') {
    return <CopilotMessage content={choice.delta.content} />
  }

  const toolFunction = tool?.function
  if (!tool || !tool.id || !toolFunction) {
    return null
  }

  let component = null

  try {
    component = (
      <ToolRenderer
        name={toolFunction.name}
        delta={choice.delta}
        // Defensively replace newlines that may appear in JSON to avoid possible parsing errors
        // This may not be needed if the backend is already handling this correctly, but better safe than sorry
        args={JSON.parse(toolFunction.arguments.replace(/\n/g, '\\n'))}
      />
    )
  } catch {
    component = (
      <Tool title={'Error parsing tool call arguments'} isError>
        <ToolPrimaryContent language={'text'} markdown={toolFunction.arguments} />
      </Tool>
    )
  }

  if (choice.delta.reasoning_text) {
    return (
      <>
        <ReasoningText content={choice.delta.reasoning_text} />
        {component}
      </>
    )
  }

  return component
}

function LogEntryChoiceDeprecated({choice, toolResultIds}: LogEntryChoiceProps) {
  const tool = choice.delta.tool_calls?.[0]
  const toolFunction = tool?.function

  // Skip rendering tool calls that already have results elsewhere
  if (
    tool &&
    tool.id &&
    toolResultIds.has(tool.id) &&
    !('content' in choice.delta) &&
    !('reasoning_text' in choice.delta)
  ) {
    return null
  }

  let component = null
  if (toolFunction) {
    try {
      component = (
        <ToolRenderer
          name={toolFunction.name}
          delta={choice.delta}
          // Defensively replace newlines that may appear in JSON to avoid possible parsing errors
          // This may not be needed if the backend is already handling this correctly, but better safe than sorry
          args={JSON.parse(toolFunction.arguments.replace(/\n/g, '\\n'))}
        />
      )
    } catch {
      component = (
        <Tool title={'Error parsing tool call arguments'} isError>
          <ToolPrimaryContent language={'text'} markdown={toolFunction.arguments} />
        </Tool>
      )
    }
  } else if (choice.delta.content && choice.delta.role === 'assistant') {
    component = <CopilotMessage content={choice.delta.content} />
  }

  if (choice.delta.reasoning_text) {
    return (
      <>
        {component}
        <ReasoningText content={choice.delta.reasoning_text} />
      </>
    )
  }

  return component
}

function CopilotMessage({content}: {content: string}) {
  const isStripEnabled = useFeatureFlag('logs_pr_tag_strip')
  if (isStripEnabled) {
    content = content.replace(/<pr_title>.*?<\/pr_title>|<pr_description>.*?<\/pr_description>/gs, '')
  }
  return <MarkdownRenderer markdown={content} />
}

function ReasoningText({content}: {content: string}) {
  return <MarkdownRenderer markdown={content} />
}

import {BingIcon} from '@github-ui/copilot-reference-preview/components/WebSearchReferencePreview'
import {
  BookIcon,
  CommentDiscussionIcon,
  FileIcon,
  PlayIcon,
  SearchIcon,
  ShieldIcon,
  TagIcon,
  TasklistIcon,
} from '@primer/octicons-react'
import {Box, Heading, Text, Truncate} from '@primer/react'
import {useMemo} from 'react'

import type {CopilotChatManager} from '../utils/copilot-chat-manager'
import {
  type CopilotChatReference,
  type FunctionArguments,
  type SkillExecution,
  SUPPORTED_FUNCTIONS,
} from '../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {copilotLocalStorage} from '../utils/copilot-local-storage'
import {
  BingFunctionButton,
  BingGroundingFunctionButton,
  CodeSearchButton,
  FigmaButton,
  GetAlertButton,
  GetDiscussionButton,
  GetFileButton,
  GetFileChangesButton,
  GetGitHubDataButton,
  GetJobLogsButton,
  getJobLogsSkillExecutionTopic,
  KnowledgeBaseSearchButton,
  PlanButton,
  SupportSearchButton,
} from './FunctionCallButton'

export const CodeSearchIcon = () => <SearchIcon />
export const GetFileIcon = () => <FileIcon />
const ReleaseIcon = () => <TagIcon />
const JobIcon = () => <PlayIcon />
const KnowledgeBaseIcon = () => <BookIcon />
const DiscussionIcon = () => <CommentDiscussionIcon />
const PlanIcon = () => <TasklistIcon />

const DEFAULT_RESPONDING_MESSAGE = 'planning response'

interface FunctionMetadata {
  id: string
  loadingText: string
  completedText: string
  icon: () => JSX.Element
  referenceType?: CopilotChatReference['type']
  name: string
  activeSkillText: string
}

export const functionMetadataCollection = (args: FunctionArguments): FunctionMetadata | undefined => {
  switch (args.kind) {
    case 'bing-search':
      return {
        id: 'bing-search',
        referenceType: 'web-search',
        loadingText: `Using Bing to search for "${args.query}"`,
        completedText: `Bing results for "${args.query}"`,
        icon: BingIcon,
        name: 'Bing search',
        activeSkillText: 'searching Bing',
      }
    case 'lexical-code-search':
      return {
        id: 'codesearch',
        loadingText: `Search for "${args.query}" in "${args.scopingQuery}"`,
        completedText: `Search results for "${args.query}" in "${args.scopingQuery}"`,
        icon: CodeSearchIcon,
        name: 'Code search',
        activeSkillText: 'searching the codebase',
      }
    case 'semantic-code-search':
      return {
        id: 'codesearch',
        loadingText: `Search for "${args.query}" in "${args.repoOwner}/${args.repoName}"`,
        completedText: `Search results for "${args.query}" in "${args.repoOwner}/${args.repoName}"`,
        icon: CodeSearchIcon,
        name: 'Code search',
        activeSkillText: 'searching the codebase',
      }
    case 'kb-search':
      return {
        id: 'kb-search',
        loadingText: `Searching for "${args.query}" in the knowledge base`,
        completedText: `Knowledge base search results for "${args.query}"`,
        icon: KnowledgeBaseIcon,
        name: 'Knowledge base search',
        activeSkillText: 'searching the knowledge base',
      }
    case 'getalert':
      return {
        id: 'getalert',
        loadingText: `Retrieving information about alerts`,
        completedText: `Including information about alerts`,
        icon: () => <ShieldIcon />,
        name: 'Get alert',
        activeSkillText: 'getting alert',
      }
    case 'get-github-data': {
      return {
        id: 'get-github-data',
        loadingText: `Fetching ${args.endpoint}`,
        completedText: `Results of ${args.endpoint}`,
        icon: ReleaseIcon,
        name: 'Get GitHub Data',
        activeSkillText: 'getting data',
      }
    }
    case 'get-actions-job-logs': {
      const topic = getJobLogsSkillExecutionTopic(args)
      const capitalizedTopic = topic.charAt(0).toUpperCase() + topic.slice(1)
      return {
        id: 'get-actions-jog-logs',
        loadingText: `Retrieving ${topic} in ${args.repo}`,
        completedText: `${capitalizedTopic} in ${args.repo}`,
        icon: JobIcon,
        name: 'Get job logs',
        activeSkillText: 'getting job logs',
      }
    }
    case 'getdiscussion': {
      return {
        id: 'getdiscussion',
        loadingText: `Fetching discussion ${args.discussionNumber}`,
        completedText: `Details about discussion #${args.discussionNumber}`,
        icon: DiscussionIcon,
        name: 'Get discussion',
        activeSkillText: 'getting discussion',
      }
    }
    case 'getfile': {
      return {
        id: 'getfile',
        loadingText: `Searching for file`,
        completedText: `Using results of get file`,
        icon: GetFileIcon,
        name: 'Get file',
        activeSkillText: 'searching for file',
      }
    }
    case 'getfilechanges': {
      return {
        id: 'getfilechanges',
        loadingText: `Searching for file changes`,
        completedText: `File changes for ${args.path} in ${args.repo}`,
        icon: GetFileIcon,
        name: 'Get file changes',
        activeSkillText: 'searching for file changes',
      }
    }
    case 'planskill': {
      return {
        id: 'planskill',
        loadingText: `Planning response...`,
        completedText: `Plan created`,
        icon: PlanIcon,
        name: 'Plan skill',
        activeSkillText: 'planning response',
      }
    }
    case 'support-search': {
      return {
        id: 'supportsearch',
        loadingText: `Searching for support documents`,
        completedText: `Using results of support search`,
        icon: KnowledgeBaseIcon,
        name: 'Support search',
        activeSkillText: 'searching for support documents',
      }
    }
    case 'get-figma': {
      return {
        id: 'getfigma',
        loadingText: 'Analyzing Figma file',
        completedText: 'Using results of Figma file',
        icon: KnowledgeBaseIcon,
        name: 'Get Figma',
        activeSkillText: 'analyzing Figma file',
      }
    }
    case 'codesearchagentskill': {
      return {
        id: 'codesearchagentskill',
        loadingText: 'Using the code search agent',
        completedText: 'Using results of code search agent',
        icon: KnowledgeBaseIcon,
        name: 'Code Search Agent',
        activeSkillText: 'searching the codebase',
      }
    }
  }
}

function FunctionCompleted({maxWidth, functionMetadata}: {maxWidth: number; functionMetadata: FunctionMetadata}) {
  return (
    <>
      {functionMetadata.icon()}
      <Truncate title={functionMetadata.completedText} sx={{maxWidth}}>
        {functionMetadata.completedText}
      </Truncate>
    </>
  )
}

function FunctionLoading({maxWidth, functionMetadata}: {maxWidth: number; functionMetadata: FunctionMetadata}) {
  return (
    <>
      {functionMetadata.icon()}
      <Truncate title={functionMetadata.loadingText} sx={{maxWidth}}>
        {functionMetadata.loadingText}
      </Truncate>
    </>
  )
}

function FunctionError({
  functionCall,
  functionMetadata,
}: {
  functionCall: SkillExecution
  functionMetadata: FunctionMetadata
}) {
  return (
    <Box sx={{p: 2}}>
      <Heading as="h3" sx={{fontSize: 1}}>
        An error occurred while {functionMetadata.activeSkillText}
      </Heading>
      <Text as="p" sx={{m: 0}}>
        {functionCall.errorMessage}
      </Text>
      <Text
        as="p"
        sx={{
          mt: 2,
          mb: 0,
          fontSize: 0,
          fontWeight: 'normal',
          color: 'fg.subtle',
        }}
      >
        Copilot used the <Text sx={{fontWeight: 'semibold'}}>{functionMetadata.name}</Text> tool
      </Text>
    </Box>
  )
}

function FunctionTitle({
  functionCall,
  functionMetadata,
  panelWidth,
}: {
  functionCall: SkillExecution
  functionMetadata: FunctionMetadata
  panelWidth: number | undefined
}) {
  const maxWidth = panelWidth ? panelWidth - 130 : copilotLocalStorage.DEFAULT_PANEL_WIDTH
  const innerElement =
    functionCall?.status === 'error' ? (
      <FunctionError functionCall={functionCall} functionMetadata={functionMetadata} />
    ) : functionCall?.status === 'completed' ? (
      <FunctionCompleted maxWidth={maxWidth} functionMetadata={functionMetadata} />
    ) : (
      <FunctionLoading maxWidth={maxWidth} functionMetadata={functionMetadata} />
    )

  return <Box sx={{display: 'flex', gap: '6px', alignItems: 'center'}}>{innerElement}</Box>
}

function functionRenderer(
  functionCall: SkillExecution,
  functionMetadata: FunctionMetadata,
  manager: CopilotChatManager,
  panelWidth: number | undefined,
  parsedArgs: FunctionArguments,
  useSelectReference: boolean,
) {
  // We may need a better way to indicate that a function call failed due to a confirmation error
  // like a status of confirmationNeeded or some other flag.
  if (functionCall && functionCall.errorMessage !== 'confirmation error') {
    const commonProps = {functionCall, functionMetadata, panelWidth, parsedArgs}

    switch (parsedArgs.kind) {
      case 'bing-search':
        if (copilotFeatureFlags.bingGroundingUIEnabled) {
          return (
            <BingGroundingFunctionButton
              chatManager={manager}
              functionCall={functionCall}
              skillArgs={parsedArgs}
              useSelectReference={useSelectReference}
            />
          )
        } else {
          return (
            <BingFunctionButton
              chatManager={manager}
              functionCall={functionCall}
              skillArgs={parsedArgs}
              useSelectReference={useSelectReference}
            />
          )
        }
      case 'lexical-code-search':
      case 'semantic-code-search':
        return (
          <CodeSearchButton
            chatManager={manager}
            functionCall={functionCall}
            skillArgs={parsedArgs}
            useSelectReference={useSelectReference}
          />
        )
      case 'getalert':
        return (
          <GetAlertButton
            chatManager={manager}
            functionCall={functionCall}
            skillArgs={parsedArgs}
            useSelectReference={useSelectReference}
          />
        )
      case 'getfile':
        return (
          <GetFileButton
            chatManager={manager}
            functionCall={functionCall}
            skillArgs={parsedArgs}
            useSelectReference={useSelectReference}
          />
        )
      case 'getfilechanges':
        return (
          <GetFileChangesButton
            chatManager={manager}
            functionCall={functionCall}
            skillArgs={parsedArgs}
            useSelectReference={useSelectReference}
          />
        )
      case 'getdiscussion':
        return (
          <GetDiscussionButton
            chatManager={manager}
            functionCall={functionCall}
            skillArgs={parsedArgs}
            useSelectReference={useSelectReference}
          />
        )
      case 'get-actions-job-logs':
        return (
          <GetJobLogsButton
            chatManager={manager}
            functionCall={functionCall}
            skillArgs={parsedArgs}
            useSelectReference={useSelectReference}
          />
        )
      case 'kb-search':
        return (
          <KnowledgeBaseSearchButton
            chatManager={manager}
            functionCall={functionCall}
            skillArgs={parsedArgs}
            useSelectReference={useSelectReference}
          />
        )
      case 'planskill':
        return (
          <PlanButton
            chatManager={manager}
            functionCall={functionCall}
            skillArgs={parsedArgs}
            useSelectReference={useSelectReference}
          />
        )
      case 'get-github-data':
        return (
          <GetGitHubDataButton
            chatManager={manager}
            functionCall={functionCall}
            skillArgs={parsedArgs}
            useSelectReference={useSelectReference}
          />
        )
      case 'support-search':
        return (
          <SupportSearchButton
            chatManager={manager}
            functionCall={functionCall}
            skillArgs={parsedArgs}
            useSelectReference={useSelectReference}
          />
        )
      case 'get-figma':
        if (!copilotFeatureFlags.immersiveFigmaIntegration) return <></>
        return (
          <FigmaButton
            chatManager={manager}
            functionCall={functionCall}
            skillArgs={parsedArgs}
            useSelectReference={useSelectReference}
          />
        )
      default: {
        return (
          <div className={`border rounded-2 p-2`}>
            <FunctionTitle {...commonProps} />
          </div>
        )
      }
    }
  } else {
    return null
  }
}

export function useFunctionMetadata(functionCall: SkillExecution): {
  functionMetadata: FunctionMetadata | undefined
  functionRenderer: typeof functionRenderer | undefined
  parsedArgs: FunctionArguments | undefined
} {
  return useMemo(() => {
    if (!functionCall.arguments || !SUPPORTED_FUNCTIONS.includes(functionCall.slug)) {
      return {
        functionMetadata: undefined,
        functionRenderer: undefined,
        parsedArgs: undefined,
      }
    }
    const parsedArgs = {
      ...JSON.parse(functionCall.arguments),
      kind: functionCall.slug,
    } as FunctionArguments
    const functionMetadata = functionMetadataCollection(parsedArgs)

    return {
      functionMetadata,
      functionRenderer,
      parsedArgs,
    }
  }, [functionCall])
}

export function messageFromFunctionCall(functionCall?: SkillExecution) {
  if (!functionCall) return DEFAULT_RESPONDING_MESSAGE
  const functionMetadata = metadataFromFunctionCall(functionCall)

  return functionCall.statusMessage ?? functionMetadata?.activeSkillText ?? DEFAULT_RESPONDING_MESSAGE
}

export function metadataFromFunctionCall(functionCall: SkillExecution) {
  if (!functionCall) return undefined

  const parsedArgs = {
    ...JSON.parse(functionCall?.arguments || '{}'),
    kind: functionCall.slug,
  } as FunctionArguments

  return functionMetadataCollection(parsedArgs)
}

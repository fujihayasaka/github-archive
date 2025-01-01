import {MarkdownRenderer} from '@github-ui/copilot-markdown'
import {ToolHeader} from './ToolHeader'
import toolCodeBlockExtension, {type ToolCodeBlockExtensionArgs} from './code-block/ToolCodeBlockExtension'
import type {
  AsyncBashToolArgs,
  BashToolArgs,
  Delta,
  ReadAsyncBashToolArgs,
  ReplyToCommentToolArgs,
  ReportProgressToolArgs,
  StopAsyncBashToolArgs,
  StrReplaceEditorToolArgs,
  ThinkToolArgs,
  ToolArgs,
  ToolName,
} from '../../types/session'
import {extractContentFromDiff} from '../../utils/extract-content-from-diff'
import {Details, Stack, Text, useDetails} from '@primer/react'
import type {ReactNode} from 'react'
import {SkeletonText} from '@primer/react/experimental'
import {trimFileName} from '../../utils/trim-file-name'
import styles from './Tool.module.css'

const wrapInCodeBlock = ({language, markdown}: {language: string; markdown: string}) => {
  if (!markdown) {
    return `~~~\nNothing to display\n~~~`
  }

  // Use ~~~ for the delimiter to avoid conflicts with backticks. This is acceptable by remark-gfm, the underlying rendering library.
  return `~~~${language}\n${markdown}\n~~~`
}

export function ToolRenderer({name, delta, args}: {name: ToolName; delta: Delta; args: ToolArgs}) {
  switch (name) {
    case 'bash': {
      const bashArgs = args as BashToolArgs
      const input = `$ ${bashArgs.command}`
      const {isError, content: output} = parseContent(delta.content)

      return (
        <Tool title={'Bash'} isError={isError}>
          <ToolPrimaryContent
            language={bashArgs.command?.startsWith('git diff') ? 'diff' : 'bash'}
            markdown={`${input}${output ? `\n${output}` : ''}`}
            bashLoading={output === undefined}
          />
        </Tool>
      )
    }
    case 'async_bash': {
      const asyncBashArgs = args as AsyncBashToolArgs
      const input = `$ ${asyncBashArgs.command}`
      const {isError, content: output} = parseContent(delta.content)

      return (
        <Tool title={`Start or send input to long-running Bash session ${asyncBashArgs.sessionId}`} isError={isError}>
          <ToolPrimaryContent
            language="bash"
            markdown={`${input}${output ? `\n${output}` : ''}`}
            bashLoading={output === undefined}
          />
        </Tool>
      )
    }
    case 'read_async_bash': {
      const readAsyncBashArgs = args as ReadAsyncBashToolArgs
      const {isError, content: output} = parseContent(delta.content)

      return (
        <Tool title={`View logs from long-running Bash session ${readAsyncBashArgs.sessionId}`} isError={isError}>
          <ToolPrimaryContent language="bash" markdown={output ? output : ''} bashLoading={output === undefined} />
        </Tool>
      )
    }
    case 'stop_async_bash': {
      const stopAsyncBashArgs = args as StopAsyncBashToolArgs
      const {isError, content: output} = parseContent(delta.content)

      return (
        <Tool title={`Stop long-running Bash session ${stopAsyncBashArgs.sessionId}`} isError={isError}>
          <ToolPrimaryContent language="bash" markdown={output ? output : ''} bashLoading={output === undefined} />
        </Tool>
      )
    }
    case 'think': {
      const thinkArgs = args as ThinkToolArgs
      const {isError, content: output} = parseContent(thinkArgs.thought)

      return (
        <Tool title={'Thought'} isError={isError}>
          <ToolPrimaryContent language="markdown" markdown={output} />
        </Tool>
      )
    }
    case 'str_replace_editor': {
      const strReplaceEditorArgs = args as StrReplaceEditorToolArgs
      const fileExtension = strReplaceEditorArgs.path?.split('.').pop() || ''
      // TODO: We need a more robust way to determine the language from the file extension using a pre-existing library mapper
      const language = fileExtension === 'md' ? 'markdown' : fileExtension || 'text'
      const {isError, content: parsedContent} = parseContent(delta.content)
      switch (strReplaceEditorArgs.command) {
        case 'create':
        case 'insert':
        case 'view':
        case 'undo_edit': {
          // TODO: differentiate files/directory for str_replace_editor/view
          const output = extractContentFromDiff(parsedContent)

          const filePath = trimFileName(strReplaceEditorArgs.path)
          const displayPath =
            filePath +
            getPathSuffix(
              strReplaceEditorArgs.command,
              strReplaceEditorArgs.view_range,
              strReplaceEditorArgs.insert_line,
            )

          return (
            <Tool
              title={getCommandTitle({
                command: strReplaceEditorArgs.command,
                path: strReplaceEditorArgs.path,
              })}
              isError={isError}
              path={filePath ? displayPath : undefined}
            >
              <ToolPrimaryContent language={language} markdown={output} />
            </Tool>
          )
        }
        case 'str_replace': {
          const output = parsedContent?.trim()
          return (
            <Tool
              title={getCommandTitle({
                command: strReplaceEditorArgs.command,
                path: strReplaceEditorArgs.path,
              })}
              isError={isError}
              path={trimFileName(strReplaceEditorArgs.path)}
            >
              <ToolPrimaryContent language={'diff'} markdown={output} />
            </Tool>
          )
        }
      }
      // This actually isn't needed, but the linter complains if we don't have it.
      break
    }
    case 'report_progress': {
      const reportProgressArgs = args as ReportProgressToolArgs
      const {isError: inputError, content: input} = parseContent(reportProgressArgs.prDescription)
      const {isError: outputError, content: output} = parseContent(delta.content)

      return (
        <Tool title={`Progress Update: ${reportProgressArgs.commitMessage}`} isError={inputError || outputError}>
          <ToolPrimaryContent language="markdown" markdown={input} />
          <ToolSecondaryContent type="output" language="json" markdown={output} />
        </Tool>
      )
    }

    // TODO: We have the comment_id in the args, so we can link to the comment in the UI once we have a design
    case 'reply_to_comment': {
      const replyToCommentArgs = args as ReplyToCommentToolArgs
      const {isError, content: output} = parseContent(replyToCommentArgs.reply)
      return (
        <Tool title={'Reply to Comment'} isError={isError}>
          <ToolPrimaryContent language={'markdown'} markdown={output} />
        </Tool>
      )
    }

    default: {
      const {isError, content} = parseContent(delta.content)
      const {language: outputLanguage, output} = parseGenericToolOutput(content)
      const input = JSON.stringify(args, null, 2)
      const title = `Call to ${name}`

      return (
        <Tool title={title} isError={isError}>
          <ToolPrimaryContent language={outputLanguage} markdown={output} />
          <ToolSecondaryContent type="input" language="json" markdown={input} />
        </Tool>
      )
    }
  }
}

const parseGenericToolOutput = (content: string | undefined): {language: string; output: string | undefined} => {
  if (typeof content === 'undefined') {
    return {language: 'text', output: content}
  }

  try {
    const parsedOutput = JSON.parse(content)
    const output = JSON.stringify(parsedOutput, null, 2)
    return {language: 'json', output}
  } catch {
    return {language: 'text', output: content}
  }
}

export function Tool({
  title,
  isError = false,
  path,
  children,
}: {
  title: string
  isError: boolean
  path?: string
  children: ReactNode
}) {
  const {getDetailsProps} = useDetails({defaultOpen: true})
  return (
    <Details
      {...getDetailsProps()}
      className={`${styles.detailsContainer} border rounded overflow-hidden bgColor-default`}
    >
      <ToolHeader title={title} path={path} isCollapsed={!getDetailsProps().open} isError={isError} />
      {children}
    </Details>
  )
}

export function ToolPrimaryContent({
  language,
  markdown,
  ...extensionProps
}: {
  language: string
  markdown: string | undefined
} & ToolCodeBlockExtensionArgs) {
  return markdown === undefined ? (
    <MarkdownLoading />
  ) : (
    <MarkdownRenderer
      markdown={wrapInCodeBlock({
        language,
        markdown,
      })}
      extensions={[toolCodeBlockExtension({characterCount: markdown.length, ...extensionProps})]}
    />
  )
}

function ToolSecondaryContent({
  type,
  language,
  markdown,
}: {
  type: 'input' | 'output'
  language: string
  markdown: string | undefined
}) {
  return (
    <Stack direction="vertical" padding="normal" gap="condensed" className="border-top bgColor-inset">
      <Text size="small" weight="medium" className={'fgColor-muted'}>
        {type === 'input' ? 'Input' : 'Output'}
      </Text>
      {markdown === undefined ? (
        <MarkdownLoading />
      ) : (
        <MarkdownRenderer
          className="border rounded bgColor-default overflow-hidden"
          markdown={wrapInCodeBlock({
            language,
            markdown,
          })}
          extensions={[toolCodeBlockExtension({characterCount: markdown.length})]}
        />
      )}
    </Stack>
  )
}

function MarkdownLoading({lines = 3, maxWidth = '45ch'}: {lines?: number; maxWidth?: string}) {
  return (
    // Padding matches the default padding of the MarkdownRenderer
    <div className="py-3 px-4">
      {/* eslint-disable-next-line primer-react/no-system-props */}
      <SkeletonText lines={lines} maxWidth={maxWidth} />
    </div>
  )
}

// Parses the delta.content for <error> tags to detect errors and remove tags from content
function parseContent(content?: string): {isError: boolean; content: string | undefined} {
  if (!content) return {isError: false, content}

  const errorRegex = /<error>(.*?)<\/error>/s
  const match = content.match(errorRegex)

  if (match && match[1] !== undefined) {
    return {
      isError: true,
      content: match[1], // This gets the content between the error tags
    }
  }

  return {isError: false, content}
}

const getCommandTitle = ({command, path}: {command: StrReplaceEditorToolArgs['command']; path: string}) => {
  const hasPath = !!trimFileName(path)?.length

  switch (command) {
    case 'create':
      return 'Create'
    case 'insert':
      return 'Insert lines at'
    case 'view':
      return `View${hasPath ? '' : ' repository'}`
    case 'str_replace':
      return 'Edit'
    case 'undo_edit':
      return 'Undo edit'
    default:
      return command || 'Unknown'
  }
}

const getPathSuffix = (command: StrReplaceEditorToolArgs['command'], viewRange?: number[], insertLine?: number) => {
  if (command === 'view' && viewRange) {
    return `:${viewRange[0]}-${viewRange[1]}`
  }

  if (command === 'insert' && insertLine !== undefined) {
    return `:${insertLine}`
  }

  return ''
}

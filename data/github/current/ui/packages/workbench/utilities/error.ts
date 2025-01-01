type SparkErrorSource = 'editor' | 'preview-build' | 'preview-runtime' | 'deploy'

export type SparkError = {
  source: SparkErrorSource
  messageRaw: string
  messagePretty?: string
  path?: string
  line?: number
  column?: number
  location?: string
}

export const fixAllPrompt = 'Fix all reported errors.'
export const fixSuggestionPrompt = 'Fix these build errors:'

export const attachedErrorsPromptPrefix = 'Fix all the following errors:'
export const generateErrorsPrompt = (inputValue: string, errors: string[]) =>
  `${inputValue} ${attachedErrorsPromptPrefix} ${errors.join('; ')}`

const pathPrefixes = ['/workspaces/workbench-template/', '/workspaces/spark/', '/workspaces/spark-template/']
export const parsePath = (path?: string) => {
  if (!path) return path
  let processedPath = path

  for (const prefix of pathPrefixes) {
    if (processedPath.startsWith(prefix)) {
      processedPath = processedPath.substring(prefix.length)
      break
    }
  }

  // Remove leading slash if present
  if (processedPath.startsWith('/')) {
    processedPath = processedPath.substring(1)
  }

  // check for '?' and remove it and everything after
  const questionMarkIndex = processedPath.indexOf('?')
  if (questionMarkIndex !== -1) {
    processedPath = processedPath.substring(0, questionMarkIndex)
  }

  return processedPath
}

export const parseLocation = (line?: number, column?: number) => {
  let location = ''
  if (line) {
    location += `:${line}`
    if (column) {
      location += `:${column}`
    }
  }
  return location
}

// Create utility function to parse and format error information
export const parseRawError = (source: SparkErrorSource, message: string): SparkError => {
  // TypeScript error format: filepath(line,column): error code: message
  const tsErrorRegex = /^([^(]+)\((\d+),(\d+)\):\s+(error|warning)\s+([^:]+):\s+(.+)$/
  let match = message.match(tsErrorRegex)
  if (match) {
    const path = parsePath(match[1])
    const line = parseInt(match[2] || '', 10)
    const column = parseInt(match[3] || '', 10)
    const errorType = match[4]
    const errorCode = match[5]
    const errorMessage = match[6]
    const messagePretty = `${errorType} ${errorCode}: ${errorMessage}`
    const location = parseLocation(line, column)

    return {
      source,
      messageRaw: message,
      messagePretty,
      path,
      line,
      column,
      location,
    }
  }

  // Handle CSS parsing errors with line/column numbers that could be undefined or actual numbers
  const cssErrorRegex = /^(.*?)\s+at\s+([^:]+):([^:]+):([^:]+)$/ms
  match = message.match(cssErrorRegex)
  if (match) {
    const errorMessage = match[1]?.trim()
    const path = parsePath(match[2])

    // Parse line and column - they could be actual numbers or "undefined"
    const lineStr = match[3] ?? 'undefined'
    const columnStr = match[4] ?? 'undefined'

    // Convert to numbers only if they're not "undefined"
    const line = lineStr !== 'undefined' ? parseInt(lineStr, 10) : undefined
    const column = columnStr !== 'undefined' ? parseInt(columnStr, 10) : undefined
    const location = parseLocation(line, column)

    return {
      source,
      messageRaw: message,
      messagePretty: errorMessage?.replace(/\s*\(\d+:\d+\)/, ''),
      path,
      line,
      column,
      location,
    }
  }

  // Preview server errors (original pattern)
  const genericErrorRegex = /^([^(]+)\s+\((\d+):(\d+)\)([\s\S]*?)at\s+([^:]+):(\d+):(\d+)/
  match = message.match(genericErrorRegex)
  if (match) {
    const messagePrefix = match[1]?.trim() // Extract the error message prefix
    const codeSnippet = match[4]?.trim() // Extract the code snippet showing the error
    const messagePretty = `${messagePrefix}\n${codeSnippet}`

    // Extract file information from the regex match
    const path = parsePath(match[5])
    const line = parseInt(match[6] || '', 10)
    const column = parseInt(match[7] || '', 10)
    const location = parseLocation(line, column)

    return {
      source,
      messageRaw: message,
      messagePretty,
      path,
      line,
      column,
      location,
    }
  }

  return {
    source,
    messageRaw: message,
    messagePretty: message,
  }
}

export const getUniqueErrors = (errors: SparkError[]) => {
  const uniqueErrors = new Set<string>()
  return errors.filter(error => {
    if (uniqueErrors.has(error.messageRaw)) {
      return false
    }
    uniqueErrors.add(error.messageRaw)
    return true
  })
}

export const getErrorSourceLabel = (source?: string) => {
  if (source === 'deploy') return 'Deployment error'
  if (source === 'preview-build') return 'Build error'
  if (source === 'preview-runtime') return 'Runtime error'
  if (source === 'editor') return 'Syntax error'
  return 'Error'
}

import {getStream} from './ai'
import {getPrContext} from './get-pr-context'

import {searchCode} from './search-code'
import type {
  AnswerProgress,
  AnswerStatus,
  CodebaseQuestion,
  DiffHunk,
  HydratedIssueReference,
  PullRequest,
  SearchInfo,
} from './types'

export async function* streamingGenerateAnswer(
  apiUrl: string,
  question: string,
  pullRequest: PullRequest,
  mentionedIssues: HydratedIssueReference[],
  diffHunks: DiffHunk[],
): AsyncIterable<AnswerProgress> {
  const owner = pullRequest.base.repo.owner.login
  const repo = pullRequest.base.repo.name
  try {
    const statusStream: AnswerStatus = {
      step: 'generating-questions',
      message: 'Thinking...',
    }
    yield statusStream

    // STEP 1: Generate up to 3 questions about the codebase
    yield {
      step: 'generating-questions',
      message: 'Thinking about your question...',
    }

    const prContext = getPrContext(pullRequest, diffHunks, mentionedIssues)

    const codebaseQuestions = await generateCodebaseQuestions(apiUrl, question, prContext)

    // STEP 2: Search code for each question
    yield {
      step: 'searching-code',
      message: 'Searching the codebase...',
      progress: 0,
      details: `Found ${codebaseQuestions.length} questions to search for.`,
      searches: [],
    }

    const searchResults = []
    const searchInfos: SearchInfo[] = []

    for (let i = 0; i < codebaseQuestions.length; i++) {
      const q = codebaseQuestions[i]
      if (!q) {
        continue
      }

      // Update status with current search
      const currentSearch: SearchInfo = {
        question: q.question,
        totalResults: 0,
      }

      yield {
        step: 'searching-code',
        message: `Searching for "${q.question}"`,
        progress: Math.round((i / codebaseQuestions.length) * 50), // 0-50% progress during search
        details: `Question ${i + 1} of ${codebaseQuestions.length}`,
        searches: searchInfos,
        currentSearch,
      }

      const results = await searchCode(apiUrl, owner, repo, q.question)

      // Create search info with top results
      const searchInfo: SearchInfo = {
        question: q.question,
        totalResults: results.total_count,
        topResults: results.items.slice(0, 5).map(item => ({
          path: item.path,
          url: item.html_url,
        })),
      }

      // Add to search infos array
      searchInfos.push(searchInfo)

      searchResults.push({
        ...q,
        searchResults: results,
      })

      yield {
        step: 'searching-code',
        message: `Found ${results.total_count} results for "${q.question}"`,
        progress: Math.round(((i + 1) / codebaseQuestions.length) * 50), // 0-50% progress during search
        details: `Completed ${i + 1} of ${codebaseQuestions.length} searches`,
        searches: searchInfos,
      }
    }

    // STEP 3: Generate final answer with all context
    yield {
      step: 'generating-answer',
      message: 'Generating your answer...',
      progress: 50, // 50% progress when starting to generate the answer
      searches: searchInfos,
    }

    const system = `You are an AI assistant that answers questions about pull requests (PRs).
You have been provided with:
1. The PR context (title, body, related issues, and changes)
2. Results from searching the codebase with specific questions

## Instructions:
1. Use both the PR context and the codebase search results to form a comprehensive answer.
2. Cite specific code or PR details when relevant to support your answer.
3. Keep answers objective and limited to factual details from the PR context or codebase.
4. Remember, your output must be valid markdown. No other commentary.

By following these guidelines, you'll provide clear, factual answers that accurately reflect both the PR details and the broader codebase.`

    // Prepare the search results for the prompt
    const searchResultsText = searchResults
      .map((result, index) => {
        const items = result.searchResults?.items || []
        return `
Question ${index + 1}: ${result.question}
Search Results (${items.length} files found):
${items
  .map(
    (item, i) => `
File ${i + 1}: ${item.path}
URL: ${item.html_url}
Contents:
${item.contents || 'No content available'}`,
  )
  .join('\n')}
`
      })
      .join('\n---\n')

    const prompt = `Answer the following question about this pull request or the broader codebase:

  "${question}"

  Use the pull request details and the codebase search results to answer the question.

---PULL_REQUEST_CONTEXT---
${prContext}

---CODEBASE_SEARCH_RESULTS---
${searchResultsText}

  Remember, your output must be valid markdown. No other commentary.
`

    try {
      const textStream = await getStream(apiUrl, 'gpt-4o', prompt, system)

      // Initialize progress counter for streaming
      let progressCounter = 0
      const progressUpdateInterval = 10 // Update progress every 10 chunks
      let chunkCount = 0

      for await (const chunk of textStream) {
        const chunkText = chunk.choices[0]?.delta.content
        if (!chunkText) {
          continue
        }

        yield {
          step: 'data',
          message: chunkText,
        }

        // Update progress periodically during streaming
        chunkCount++
        if (chunkCount % progressUpdateInterval === 0) {
          progressCounter = Math.min(progressCounter + 1, 49) // Cap at 99% (50% base + 49% incremental)
          yield {
            step: 'generating-answer',
            message: 'Generating your answer...',
            progress: 50 + progressCounter, // 50-99% progress during answer generation
            searches: searchInfos,
          }
        }
      }

      // Mark as complete
      yield {
        step: 'complete',
        message: 'Answer complete!',
        progress: 100,
        searches: searchInfos,
      }
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('Error in streaming generation:', error)
      yield {
        step: 'error',
        message: 'Error generating answer',
        details: error instanceof Error ? error.message : 'Unknown error',
        searches: searchInfos,
      }
    }
  } catch (error) {
    yield {
      step: 'error',
      message: 'Unable to answer this question at the moment.',
      details: error instanceof Error ? error.message : 'Unknown error',
    }
  }
}

/**
 * Generate up to 3 questions about the codebase that would help answer the user's question
 */
async function generateCodebaseQuestions(
  apiUrl: string,
  question: string,
  prContext: string,
): Promise<CodebaseQuestion[]> {
  try {
    const system = `You are an AI assistant that works with a conversational agent to answer users questions about a pull request or the broader codebase.
Your specific task is to convert the user's question into a series of specific questions about the codebase. The answers to these questions will be used to answer the user's question.
Your output will be provided to a specialized code search agent that will answer your generated questions. Then, a summarization agent will use the answers to generate a final answer to the user's question.

## Instructions:
1. Analyze the user's question and the pull request context carefully.
2. Generate up to 3 specific questions about the codebase that would help answer the user's question.
3. Each question should be specific and targeted to retrieve relevant code snippets.
4. Focus on questions that would help understand the existing codebase structure, functionality, or patterns.
5. Do not ask questions about the PR itself - focus on the broader codebase.
6. Format your response as a JSON array of strings, with each string being a question.

## Examples
Example user question 1:
"How does the change in \`$lh-default\` to \`var(--text-body-lineHeight-medium, 1.4285)\` affect existing components?"
Codebase Questions you should generate:
- What components or files use the \`$lh-default\` variable?
- What is the \`$lh-default\` variable used for?

Example user question 2:
"How does the new \`reasoning\` field in \`generateObject\` impact the existing API contracts?"
Codebase Questions you should generate:
- What other fields are part of the \`generateObject\` API call?
- How is the \`generateObject\` API call implemented?
- Where is \`generateObject\` used in the codebase?

## Required output format
You must respond with a JSON array of strings, with each string being a question. Response must be a valid JSON array.  Example:
["How is authentication implemented in the UserService class?", "What database schema is used for storing user data?", "How are API errors handled in the current implementation?"]`

    const prompt = `Based on the following pull request and user question, generate up to 3 specific questions about the codebase that would help answer the user's question:

User's Question: "${question}"

---PULL_REQUEST_CONTEXT---
${prContext}`

    const textStream = await getStream(apiUrl, 'gpt-4o', prompt, system)

    // Collect the full response
    let fullResponse = ''
    for await (const chunk of textStream) {
      if (chunk.choices[0]?.delta.content) {
        fullResponse += chunk.choices[0].delta.content
      }
    }

    let parsedQuestions: string[] = []

    try {
      // Try to parse as JSON array directly
      const parsed = JSON.parse(fullResponse)
      if (Array.isArray(parsed)) {
        parsedQuestions = parsed
      }
      // Try to parse as JSON object with questions property
      else if (parsed.questions && Array.isArray(parsed.questions)) {
        parsedQuestions = parsed.questions
      }
      // Fallback
      else {
        parsedQuestions = [question] // Use the original question as fallback
      }
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error('Error parsing questions JSON:', e)
      parsedQuestions = [question] // Use the original question as fallback
    }

    // Limit to 3 questions and map to the expected format
    return parsedQuestions.slice(0, 3).map(q => ({question: q}))
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Error generating codebase questions:', error)
    // Fallback to using the original question
    return [{question}]
  }
}

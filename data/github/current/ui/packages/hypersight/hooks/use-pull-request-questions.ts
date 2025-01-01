import {useState, useEffect, useCallback} from 'react'
import {generateSuggestedQuestions} from '../utils/generate-suggested-questions'
import {useHeadings, type Heading} from '../utils/HeadingContext'
import type {PullRequest, HydratedIssueReference, DiffHunk} from '../utils/types'

export const ANSWERS_HEADING: Heading = {
  id: 'followups-section',
  level: 2,
  text: 'Follow ups',
}

// Helper to generate a consistent ID for an answer
export const getAnswerId = (question: string) => `answer-${question.slice(0, 20).replace(/\W+/g, '-').toLowerCase()}`

// Custom hook to manage questions state
export function usePullRequestQuestions(
  apiUrl: string,
  pullRequest: PullRequest,
  extractedIssues: HydratedIssueReference[],
  diffs: DiffHunk[],
) {
  const [suggestedQuestions, setSuggestedQuestions] = useState<string[]>([])
  const [askedQuestions, setAskedQuestions] = useState<string[]>([])
  const [loadingQuestions, setLoadingQuestions] = useState<string[]>([])
  const {addHeading} = useHeadings()

  useEffect(() => {
    const fetchSuggestedQuestions = async () => {
      try {
        const questions = await generateSuggestedQuestions(apiUrl, pullRequest, extractedIssues, diffs)
        setSuggestedQuestions(questions)
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error('Error fetching suggested questions:', error)
        setSuggestedQuestions(['What is the purpose of this pull request?'])
      }
    }

    fetchSuggestedQuestions()
  }, [apiUrl, pullRequest, extractedIssues, diffs])

  const handleQuestionClick = useCallback(
    (question: string) => {
      // Check if we already have this question
      if (askedQuestions.includes(question)) {
        // Scroll to the existing answer
        const answerId = getAnswerId(question)
        document.getElementById(answerId)?.scrollIntoView({behavior: 'smooth'})
        return
      }

      addHeading(ANSWERS_HEADING)

      const heading: Heading = {
        id: getAnswerId(question),
        level: 3,
        text: question,
        parentId: ANSWERS_HEADING.id,
      }

      addHeading(heading)

      // Add the question and remove it from suggested questions
      setAskedQuestions(prev => [...prev, question])
      setSuggestedQuestions(prev => prev.filter(q => q !== question))
      setLoadingQuestions(prev => [...prev, question])

      // Wait a brief moment for the answer block to render, then scroll to it
      setTimeout(() => {
        const answerId = getAnswerId(question)
        document.getElementById(answerId)?.scrollIntoView({
          behavior: 'smooth',
          block: 'start',
        })
      }, 100)
    },
    [addHeading, askedQuestions],
  )

  const handleAnswerComplete = (question: string) => {
    setLoadingQuestions(prev => prev.filter(q => q !== question))
  }

  return {
    suggestedQuestions,
    askedQuestions,
    loadingQuestions,
    handleQuestionClick,
    handleAnswerComplete,
  }
}

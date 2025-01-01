import {SuggestedQuestions} from './SuggestedQuestions'
import {AnswerBlock} from './AnswerBlock'
import type {DiffHunk, HydratedIssueReference, PullRequest} from '../utils/types'
import {QuestionInput} from './QuestionInput'
import {ANSWERS_HEADING, getAnswerId, usePullRequestQuestions} from '../hooks/use-pull-request-questions'

type PullRequestQuestionsProps = {
  apiUrl: string
  pullRequest: PullRequest
  extractedIssues: HydratedIssueReference[]
  diffs: DiffHunk[]
}

// Component for the questions section
function QuestionSection({
  suggestedQuestions,
  onQuestionClick,
}: {
  suggestedQuestions: string[]
  onQuestionClick: (question: string) => void
}) {
  return (
    <div className="questions-section">
      <SuggestedQuestions questions={suggestedQuestions} onQuestionClick={onQuestionClick} />
    </div>
  )
}

// Component for the answers section
function AnswerSection({
  apiUrl,
  questions,
  pullRequest,
  extractedIssues,
  diffs,
  loadingQuestions,
  onAnswerComplete,
}: {
  apiUrl: string
  questions: string[]
  pullRequest: PullRequest
  extractedIssues: HydratedIssueReference[]
  diffs: DiffHunk[]
  loadingQuestions: string[]
  onAnswerComplete: (question: string) => void
}) {
  if (!questions.length) return null

  return (
    <div>
      <h2 className="mb-4 px-3" id={ANSWERS_HEADING.id}>
        {ANSWERS_HEADING.text}
      </h2>
      {questions.map(question => (
        <AnswerBlock
          apiUrl={apiUrl}
          key={question}
          question={question}
          pullRequest={pullRequest}
          extractedIssues={extractedIssues}
          diffs={diffs}
          id={getAnswerId(question)}
          onAnswerComplete={() => onAnswerComplete(question)}
          isLoading={loadingQuestions.includes(question)}
        />
      ))}
    </div>
  )
}

export function PullRequestQuestions({apiUrl, pullRequest, extractedIssues, diffs}: PullRequestQuestionsProps) {
  const {suggestedQuestions, askedQuestions, loadingQuestions, handleQuestionClick, handleAnswerComplete} =
    usePullRequestQuestions(apiUrl, pullRequest, extractedIssues, diffs)

  return (
    <div>
      <AnswerSection
        apiUrl={apiUrl}
        questions={askedQuestions}
        pullRequest={pullRequest}
        extractedIssues={extractedIssues}
        diffs={diffs}
        loadingQuestions={loadingQuestions}
        onAnswerComplete={handleAnswerComplete}
      />

      <QuestionSection suggestedQuestions={suggestedQuestions} onQuestionClick={handleQuestionClick} />
      <QuestionInput isAnswering={loadingQuestions.length > 0} onSubmit={handleQuestionClick} />
    </div>
  )
}

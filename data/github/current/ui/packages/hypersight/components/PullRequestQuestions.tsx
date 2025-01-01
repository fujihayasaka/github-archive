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

export function PullRequestQuestions({apiUrl, pullRequest, extractedIssues, diffs}: PullRequestQuestionsProps) {
  const {suggestedQuestions, askedQuestions, loadingQuestions, handleQuestionClick, handleAnswerComplete} =
    usePullRequestQuestions(apiUrl, pullRequest, extractedIssues, diffs)

  return (
    <>
      <div className="gap-32 flex flex-col">
        <AnswerSection
          apiUrl={apiUrl}
          questions={askedQuestions}
          pullRequest={pullRequest}
          extractedIssues={extractedIssues}
          diffs={diffs}
          loadingQuestions={loadingQuestions}
          onAnswerComplete={handleAnswerComplete}
        />
        <SuggestedQuestions questions={suggestedQuestions} onQuestionClick={handleQuestionClick} />
      </div>
      <QuestionInput isAnswering={loadingQuestions.length > 0} onSubmit={handleQuestionClick} />
    </>
  )
}

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
      <h2 className="sr-only" id={ANSWERS_HEADING.id}>
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

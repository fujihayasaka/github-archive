'use client'

import {ActionList, Heading} from '@primer/react'
import {SkeletonText} from '@primer/react/experimental'

type SuggestedQuestionsProps = {
  questions: string[]
  onQuestionClick: (question: string) => void
}

export function SuggestedQuestions({questions, onQuestionClick}: SuggestedQuestionsProps) {
  return (
    <div>
      <Heading as="h2" variant="medium" id="list-heading">
        Suggested follow ups
      </Heading>
      {questions.length > 0 ? (
        <ActionList>
          {questions.map(question => (
            <ActionList.Item
              key={question}
              className="m-0"
              onSelect={() => {
                onQuestionClick(question)
              }}
            >
              {question}
            </ActionList.Item>
          ))}
        </ActionList>
      ) : (
        <SkeletonText lines={3} />
      )}
    </div>
  )
}

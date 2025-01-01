import {Button, Checkbox, CheckboxGroup, Dialog, FormControl, Textarea} from '@primer/react'
import {useState, type FormEventHandler, type RefObject} from 'react'
import type {FeedbackSubmitHandler, FeedbackOptions} from './types'

export const DEFAULT_FEEDBACK_OPTIONS = [
  {label: 'Comment is harmful or unsafe', value: 'OFFENSIVE_OR_DISCRIMINATORY'},
  {label: 'Comment is poorly formatted', value: 'POORLY_FORMATTED'},
  {label: 'Comment is not true', value: 'INCORRECT'},
  {label: 'Comment is not helpful', value: 'UNHELPFUL'},
  {label: 'Comment is attached to the wrong line(s)', value: 'INCORRECT_LINE'},
  {label: 'Code suggestion is harmful or unsafe', value: 'SUGGESTION_OFFENSIVE_OR_DISCRIMINATORY'},
  {label: 'Code suggestion is poorly formatted', value: 'SUGGESTION_POORLY_FORMATTED'},
  {label: 'Code suggestion does not solve the problem in the comment', value: 'SUGGESTION_UNHELPFUL'},
  {label: 'Code suggestion is invalid', value: 'SUGGESTION_INVALID'},
]

interface NegativeFeedbackFormProps {
  onClose: () => void
  onSubmit: FeedbackSubmitHandler
  feedbackOptions?: FeedbackOptions
  returnFocusRef: RefObject<HTMLButtonElement>
}

export const NegativeFeedbackForm: React.FC<NegativeFeedbackFormProps> = ({
  onClose,
  onSubmit,
  feedbackOptions = DEFAULT_FEEDBACK_OPTIONS,
  returnFocusRef,
}) => {
  const [dirty, setDirty] = useState(false)
  const [feedbackChoice, setFeedbackChoice] = useState<string[]>([])
  const [textResponse, setTextResponse] = useState('')

  const handleSubmit: FormEventHandler = e => {
    e.preventDefault()
    setDirty(true)

    if (feedbackChoice.length) onSubmit('NEGATIVE', feedbackChoice, textResponse)
  }

  return (
    <Dialog
      onClose={onClose}
      title="Provide additional feedback"
      subtitle="Please help us improve GitHub Copilot by sharing more details about this comment."
      returnFocusRef={returnFocusRef}
      renderBody={() => (
        <form onSubmit={handleSubmit}>
          <Dialog.Body>
            <div className="mb-3">
              <CheckboxGroup onChange={setFeedbackChoice} required>
                <CheckboxGroup.Label>Category</CheckboxGroup.Label>
                {feedbackOptions.map(opt => (
                  <FormControl key={opt.value} id={`feedback_choice_${opt.value}`}>
                    <Checkbox value={opt.value} />
                    <FormControl.Label>{opt.label}</FormControl.Label>
                  </FormControl>
                ))}
                {dirty && !feedbackChoice && (
                  <CheckboxGroup.Validation variant="error">Please select a feedback category</CheckboxGroup.Validation>
                )}
              </CheckboxGroup>
            </div>
            <FormControl id="text_response">
              <FormControl.Label>How should we improve this response?</FormControl.Label>
              <Textarea
                block
                rows={2}
                wrap="wrap"
                name="text_response"
                value={textResponse}
                resize="vertical"
                onChange={e => setTextResponse(e.currentTarget.value)}
              />
            </FormControl>
          </Dialog.Body>
          <Dialog.Footer>
            <Button type="submit" disabled={dirty && (!textResponse || !feedbackChoice)}>
              Submit
            </Button>
          </Dialog.Footer>
        </form>
      )}
    />
  )
}

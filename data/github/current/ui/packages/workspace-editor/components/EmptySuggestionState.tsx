import {CodeReviewIcon, CopilotIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'

const EmptySuggestionState = ({onAction}: {onAction?: (arg: unknown) => void}) => {
  const header = 'No open suggestions'
  const subheader = 'Suggested changes to the original pull request will be listed here for your review.'

  const reviewButtonText = 'Ask Copilot to review'

  return (
    <Blankslate>
      <Blankslate.Visual>
        <CodeReviewIcon size={24} />
      </Blankslate.Visual>
      <Blankslate.Heading>{header}</Blankslate.Heading>
      <Blankslate.Description>{subheader}</Blankslate.Description>
      {!!onAction && (
        <Blankslate.PrimaryAction href="">
          <Button onClick={onAction} leadingVisual={CopilotIcon}>
            {reviewButtonText}
          </Button>
        </Blankslate.PrimaryAction>
      )}
    </Blankslate>
  )
}

export default EmptySuggestionState

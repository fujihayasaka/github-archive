import {Button} from '@primer/react'
import {AlertIcon} from '@primer/octicons-react'

interface Props {
  isValidJSON: boolean
  resetInput: () => void
  applyInput: (input: string) => void
  content: string
  initialContent: string
}

export function PlaygroundJSONEditModeToolbar({applyInput, content, initialContent, isValidJSON, resetInput}: Props) {
  return (
    <div className="d-flex flex-justify-end flex-items-center width-full gap-2">
      <>
        <span className="color-fg-danger" aria-live="polite" aria-atomic>
          {isValidJSON ? (
            <span className="sr-only">JSON is valid</span>
          ) : (
            <>
              <AlertIcon aria-hidden /> Invalid JSON or value
            </>
          )}
        </span>
      </>
      <>
        <Button onClick={() => resetInput()} size="small">
          Cancel
        </Button>
        <Button
          variant="primary"
          onClick={() => applyInput(content)}
          size="small"
          disabled={content === initialContent || !isValidJSON}
        >
          Apply changes
        </Button>
      </>
    </div>
  )
}

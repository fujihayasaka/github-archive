import {Box, Button} from '@primer/react'
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
    <Box
      sx={{
        display: 'flex',
        justifyContent: 'flex-end',
        alignItems: 'center',
        width: '100%',
        gap: 2,
      }}
    >
      <>
        <span className="color-fg-danger">
          {!isValidJSON && (
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
    </Box>
  )
}

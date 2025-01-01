import {testIdProps} from '@github-ui/test-id-props'
import {Box, Button, IconButton} from '@primer/react'
import {HistoryIcon} from '@primer/octicons-react'

interface RestoreHistoryButtonProps {
  onClick: () => void
}

export const RestoreHistoryButton = ({onClick}: RestoreHistoryButtonProps) => {
  return (
    <Box className="position-sticky d-flex flex-justify-end" sx={{top: '1rem', marginBottom: '-2rem', zIndex: 1}}>
      <IconButton
        {...testIdProps('restore-history-button')}
        icon={HistoryIcon}
        size="small"
        onClick={onClick}
        sx={{display: ['flex', 'none', 'none']}}
        aria-label="Restore last session"
      />
      <Button size="small" onClick={onClick} sx={{display: ['none', 'flex', 'flex']}}>
        Restore last session
      </Button>
    </Box>
  )
}

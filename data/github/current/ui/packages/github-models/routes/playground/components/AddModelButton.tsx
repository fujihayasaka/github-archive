import {Box, Button, IconButton} from '@primer/react'
import type {ModelState} from '../../../types'
import {PlusIcon} from '@primer/octicons-react'

interface AddModelButtonProps {
  models: ModelState[]
  onClick: () => void
}

export const AddModelButton = ({models, onClick}: AddModelButtonProps) => {
  const isSendingMessage = models.some(m => m.isLoading)
  return (
    <Box
      className="position-sticky flex-justify-end"
      sx={{
        top: '1rem',
        marginBottom: '-2rem',
        zIndex: 1,
        display: ['none', 'flex', 'flex'],
      }}
    >
      <Button
        leadingVisual={PlusIcon}
        onClick={onClick}
        size="small"
        disabled={isSendingMessage}
        sx={{'@media screen and (max-width: 1024px)': {display: 'none'}}}
      >
        Compare
      </Button>
      <IconButton
        icon={PlusIcon}
        size="small"
        aria-label="Add model to compare"
        onClick={onClick}
        disabled={isSendingMessage}
        sx={{'@media screen and (min-width: 1025px)': {display: 'none'}}}
      />
    </Box>
  )
}

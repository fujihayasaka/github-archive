import {Button, IconButton} from '@primer/react'
import {PencilIcon} from '@primer/octicons-react'

interface PlaygroundJSONViewModeToolbarProps {
  doEdit: () => void
}

export function PlaygroundJSONViewModeToolbar({doEdit}: PlaygroundJSONViewModeToolbarProps) {
  return (
    <>
      <IconButton
        sx={{display: ['flex', 'none', 'none']}}
        size="small"
        icon={PencilIcon}
        aria-label="Edit JSON"
        onClick={doEdit}
      />
      <Button sx={{display: ['none', 'flex', 'flex']}} onClick={doEdit} size="small">
        Edit
      </Button>
    </>
  )
}

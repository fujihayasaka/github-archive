import {Box} from '@primer/react'

type ControlGroupContainerProps = {
  children: React.ReactNode
  border?: boolean
  fullWidth?: boolean
  ['data-testid']?: string
}

const ControlGroupContainer = ({
  children,
  fullWidth = false,
  border = true,
  'data-testid': testId,
}: ControlGroupContainerProps) => {
  return (
    <Box
      sx={{
        '--controlgroup_item-gap': fullWidth ? 'var(--base-size-24)' : 'var(--base-size-12)',
        borderRadius: 2,
        backgroundColor: 'canvas.default',
        border: '1px solid',
        borderColor: border ? 'border.muted' : 'transparent',
      }}
      data-testid={testId}
    >
      {children}
    </Box>
  )
}

export default ControlGroupContainer

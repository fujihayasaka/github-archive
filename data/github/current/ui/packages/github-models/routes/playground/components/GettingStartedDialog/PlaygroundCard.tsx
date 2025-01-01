import {Box} from '@primer/react'
import {ArrowUpRightIcon} from '@primer/octicons-react'

export function PlaygroundCard({
  sample,
  onClick,
  size = 'small',
}: {
  sample: string
  onClick: React.MouseEventHandler<HTMLDivElement> | undefined
  size?: 'small' | 'large'
}) {
  const sizes = {
    small: {
      p: '12px',
      fontSize: 0,
    },
    large: {
      p: 3,
      fontSize: 1,
    },
  }

  return (
    <Box
      onClick={onClick}
      sx={{
        ...sizes[size],
        borderRadius: 2,
        height: '100%',
        flex: 1,
        borderColor: 'border.muted',
        borderWidth: 1,
        borderStyle: 'solid',
        bg: 'var(--card-bgColor)',

        display: 'flex',
        boxShadow: 'var(--shadow-resting-small,var(--color-shadow-small))',
        transition: 'background-color .3s',
        gap: 3,
        ':hover': {
          bg: 'var(--control-transparent-bgColor-hover,var(--color-canvas-subtle))',
          cursor: 'pointer',
        },
      }}
    >
      <Box sx={{flex: 1}}>{sample}</Box>
      <Box sx={{color: 'fg.muted'}}>
        <ArrowUpRightIcon />
      </Box>
    </Box>
  )
}

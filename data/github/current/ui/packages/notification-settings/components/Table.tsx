import {Box} from '@primer/react'
import type {PropsWithChildren} from 'react'

function Table({children}: PropsWithChildren) {
  return (
    <Box
      sx={{
        display: 'flex',
        width: '100%',
        flexDirection: 'column',
        borderColor: 'border.default',
        borderWidth: 1,
        borderStyle: 'solid',
        borderRadius: 2,
      }}
    >
      {children}
    </Box>
  )
}

export default Table

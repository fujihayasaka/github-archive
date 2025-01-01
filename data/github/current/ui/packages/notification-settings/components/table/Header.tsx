import {Box, Heading} from '@primer/react'
import type {PropsWithChildren} from 'react'

function Header({children}: PropsWithChildren) {
  return (
    <Box
      sx={{
        backgroundColor: 'canvas.inset',
        borderRadius: 2,
        borderBottomLeftRadius: 0,
        borderBottomRightRadius: 0,
        borderColor: 'border.default',
        borderBottomWidth: 1,
        borderBottomStyle: 'solid',
      }}
    >
      <Heading as="h2" sx={{display: 'flex', justifyContent: 'space-between', fontSize: 1, mb: 0, pl: 3, py: 3}}>
        {children}
      </Heading>
    </Box>
  )
}

export default Header

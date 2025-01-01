import {Box} from '@primer/react'
import type React from 'react'

/**
 * The App component is used to render content which should be present on _all_ routes within this app
 */
export function App(props: {children?: React.ReactNode}) {
  return <Box sx={{maxWidth: '768px', ml: 'auto', mr: 'auto'}}>{props.children}</Box>
}

import {Box, Heading, Text} from '@primer/react'

import NewViewGraphic from './NewViewGraphic'

export default function NewViewExperience() {
  return (
    <Box sx={{display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', p: 7, gap: 4}}>
      <NewViewGraphic />
      <Box sx={{display: 'flex', flexDirection: 'column', alignItems: 'center'}}>
        <Heading as="h2" sx={{fontSize: 4}}>
          Build powerful views to keep track of work
        </Heading>
        <Text sx={{color: 'fg.subtle'}}>Create your own views to quickly find and access your work.</Text>
      </Box>
    </Box>
  )
}

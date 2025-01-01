import {GraphIcon} from '@primer/octicons-react'
import {Box, Heading} from '@primer/react'

import {LoadingBox} from './loading-box'

export const NoDataCard = () => {
  return (
    <LoadingBox>
      <GraphIcon className="fgColor-muted" size="medium" />
      <Heading as="h3" sx={{fontSize: 3}}>
        No data available
      </Heading>
      <Box as="p" sx={{color: 'fg.muted'}}>
        No results were returned.
      </Box>
    </LoadingBox>
  )
}

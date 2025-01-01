import {GraphIcon} from '@primer/octicons-react'
import {Heading} from '@primer/react'

import {LoadingBox} from './loading-box'

export const LoadingCard = () => {
  return (
    <LoadingBox>
      <GraphIcon className="fgColor-muted" size="medium" />
      <Heading as="h3" sx={{fontSize: 3}}>
        Loading <span className="AnimatedEllipsis" />
      </Heading>
    </LoadingBox>
  )
}

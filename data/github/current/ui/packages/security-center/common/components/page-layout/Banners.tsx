import {Box} from '@primer/react'

function Banners({children}: React.PropsWithChildren): JSX.Element {
  return <Box sx={{mb: 2}}>{children}</Box>
}

Banners.displayName = 'PageLayout.Banners'

export default Banners

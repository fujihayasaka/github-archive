import {useWindowSize, BreakpointSize} from '@primer/react-brand'
import {useMemo} from 'react'

import FeaturesTableDesktop from './FeaturesTableDesktop/FeaturesTableDesktop'
import FeaturesTableMobile from './FeaturesTableMobile/FeaturesTableMobile'

// Avoids circular dependency
import type {FeaturesTableProps} from './FeaturesTable.types'
export type {FeaturesItem, FeaturesTableProps} from './FeaturesTable.types'

const defaultProps: Partial<FeaturesTableProps> = {}

const FeaturesTable: React.FC<FeaturesTableProps> = props => {
  const initializedProps = {...defaultProps, ...props}

  const windowSize = useWindowSize()
  const isDesktopView = useMemo(
    () =>
      [BreakpointSize.LARGE, BreakpointSize.XLARGE, BreakpointSize.XXLARGE].includes(windowSize.currentBreakpointSize!),
    [windowSize],
  )

  return isDesktopView ? <FeaturesTableDesktop {...initializedProps} /> : <FeaturesTableMobile {...initializedProps} />
}

export default FeaturesTable

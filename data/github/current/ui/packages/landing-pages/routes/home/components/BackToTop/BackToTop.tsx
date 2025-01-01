import {ArrowUpIcon} from '@primer/octicons-react'
import {useEffect, useMemo, useRef, useState} from 'react'

import useIntersectionObserver from '../../../../lib/hooks/useIntersectionObserver'
import {BreakpointSize, useWindowSize} from '@primer/react-brand'
import {BREAKPOINT_DESKTOP_MIN_HEIGHT} from '../../utils/responsive'

export interface BackToTopProps {}

const COPY = {
  aria: 'Back to top',
}

const defaultProps: Partial<BackToTopProps> = {}

const BackToTop: React.FC<BackToTopProps> = props => {
  // eslint-disable-next-line unused-imports/no-unused-vars
  const initializedProps = {...defaultProps, ...props}

  const [isVisible, setIsVisible] = useState<boolean>(false)
  const heroRef = useRef<HTMLDivElement | null>(null)

  const windowSize = useWindowSize()
  const isDesktopView = useMemo(
    () =>
      [BreakpointSize.MEDIUM, BreakpointSize.LARGE, BreakpointSize.XLARGE, BreakpointSize.XXLARGE].includes(
        windowSize.currentBreakpointSize!,
      ),
    [windowSize],
  )

  const isSmallHeight = useMemo(
    () => (windowSize?.height && windowSize.height < BREAKPOINT_DESKTOP_MIN_HEIGHT) || false,
    [windowSize],
  )

  const {isIntersecting: isHeroInView} = useIntersectionObserver(
    heroRef,
    {
      threshold: {mobile: 0.15, desktop: 0.4},
    },
    !isSmallHeight && isDesktopView,
  )

  useEffect(() => {
    heroRef.current = document.querySelector('#hero')
  }, [])

  useEffect(() => {
    setIsVisible(!isHeroInView)
  }, [isHeroInView])

  return (
    <div className={`BackToTop ${isVisible ? 'BackToTop--visible' : ''}`}>
      <a href="#hero" aria-label={COPY.aria}>
        <ArrowUpIcon />
      </a>
    </div>
  )
}

export default BackToTop

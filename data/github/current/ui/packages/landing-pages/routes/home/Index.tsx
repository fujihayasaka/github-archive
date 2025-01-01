import {ThemeProvider} from '@primer/react-brand'
import {useEffect, useRef} from 'react'
import Intro from './Intro'
import Automation from './Automation'
import Security from './Security'
import Collaboration from './Collaboration'
import CustomerStories from './CustomerStories'
import Cta from './Cta'
import BackToTop from './components/BackToTop/BackToTop'
import FootnotesSection from './FootnotesSection'
import WebGLAssets from './webgl-utils/assets'

export function Home() {
  const assetsRef = useRef<WebGLAssets | null>(new WebGLAssets())
  useEffect(() => {
    let isClosed = false
    const assets = assetsRef.current
    if (assets)
      assets.load(() => {
        if (!isClosed) {
          // All assets loaded
          assets.executeCallbacks()
        }
      })
    return () => {
      isClosed = true
    }
  }, [])
  return (
    <ThemeProvider colorMode="dark" className="lp-Home">
      <Intro assetsRef={assetsRef} />
      <Automation assetsRef={assetsRef} />
      <Security assetsRef={assetsRef} />
      <Collaboration assetsRef={assetsRef} />
      <CustomerStories assetsRef={assetsRef} />
      <Cta />
      <FootnotesSection />
      <BackToTop />
    </ThemeProvider>
  )
}

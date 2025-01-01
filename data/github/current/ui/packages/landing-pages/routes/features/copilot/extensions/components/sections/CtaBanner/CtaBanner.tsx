import {Button, CTABanner as PrimerCtaBanner} from '@primer/react-brand'
import {useState, useEffect} from 'react'

import {checkPrefersReducedMotion} from '../../../../../../../lib/utils/platform'
import {COPY} from '../../../Index.data'
import {Spacer} from '../../../../../components/Spacer'
import PlayButton from '../../PlayButton/PlayButton'

interface CtaBannerProps {}

const defaultProps: Partial<CtaBannerProps> = {}

const CtaBanner: React.FC<CtaBannerProps> = props => {
  // eslint-disable-next-line unused-imports/no-unused-vars
  const initializedProps = {...defaultProps, ...props}

  const [isMounted, setIsMounted] = useState<boolean>(false)
  const [shouldReduceMotion, setShouldReduceMotion] = useState<boolean>(false)

  useEffect(() => {
    setIsMounted(true)
  }, [])

  useEffect(() => {
    if (!isMounted) return
    setShouldReduceMotion(checkPrefersReducedMotion())
  }, [isMounted])

  return (
    <section id="cta">
      <div className="fp-Section-container">
        <Spacer size="160px" size768="192px" />

        <PrimerCtaBanner className="lp-CTABanner js-cta-banner" align="center" hasShadow={false}>
          <canvas className="lp-CTABanner-background js-cta-background" />
          <canvas className="lp-CTABanner-copilot js-copilot-head" aria-label={COPY.ctaBanner.aria.copilotHead} />

          {!shouldReduceMotion && <PlayButton scene="ctaBanner" ariaLabels={COPY.aria.togglePlayButton} />}

          <PrimerCtaBanner.Heading size="2">{COPY.ctaBanner.title}</PrimerCtaBanner.Heading>
          <PrimerCtaBanner.ButtonGroup buttonsAs="a">
            <Button href={COPY.ctaBanner.cta1.url}>{COPY.ctaBanner.cta1.label}</Button>
            <Button href={COPY.ctaBanner.cta2.url}>{COPY.ctaBanner.cta2.label}</Button>
          </PrimerCtaBanner.ButtonGroup>
        </PrimerCtaBanner>
      </div>
    </section>
  )
}

export default CtaBanner

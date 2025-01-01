import {useState} from 'react'
import {LogoSuite} from '@primer/react-brand'
import {analyticsEvent} from '../../../../lib/analytics'
import {Image} from '../../../../components/Image/Image'
import {PlayIcon, PauseIcon} from '../extensions/components/CopilotIcons/CopilotIcons'

import LyftLogo from '../_assets/logos/lyft.svg'
import FedExLogo from '../_assets/logos/fedex.svg'
import ATnTLogo from '../_assets/logos/atnt.svg'
import ShopifyLogo from '../_assets/logos/shopify.svg'
import BMWLogo from '../_assets/logos/bmw.svg'
import HnMLogo from '../_assets/logos/hnm.svg'
import HoneywellLogo from '../_assets/logos/honeywell.svg'
import EyLogo from '../_assets/logos/ey.svg'
import InfosysLogo from '../_assets/logos/infosys.svg'
import BBVALogo from '../_assets/logos/bbva.svg'

export default function LogoSuiteSection() {
  const [VideoIcon, setVideoIcon] = useState(() => PauseIcon)
  const [isLogoSuiteAnimationPaused, setIsLogoSuiteAnimationPaused] = useState(false)
  const [logoSuiteAnimationButtonLabel, setLogoSuiteAnimationButtonLabel] = useState('Pause')
  const [logoSuiteAnimationButtonAriaLabel, setLogoSuiteAnimationButtonAriaLabel] = useState(
    'Logo suite animation is currently playing. Click to pause.',
  )
  const toggleLogoSuiteAnimationPause = () => {
    setIsLogoSuiteAnimationPaused(!isLogoSuiteAnimationPaused)
    if (isLogoSuiteAnimationPaused) {
      setLogoSuiteAnimationButtonAriaLabel('Logo suite animation is currently playing. Click to pause.')
      setLogoSuiteAnimationButtonLabel('Pause')
      setVideoIcon(() => PauseIcon)
    } else {
      setLogoSuiteAnimationButtonAriaLabel('Logo suite animation is paused. Click to play.')
      setLogoSuiteAnimationButtonLabel('Play')
      setVideoIcon(() => PlayIcon)
    }
  }

  const logos = [
    {src: LyftLogo, alt: 'Lyft', style: {height: '64px'}},
    {src: FedExLogo, alt: 'FedEx', style: {height: '37px'}},
    {src: ATnTLogo, alt: 'AT&T', style: {height: '47px'}},
    {src: ShopifyLogo, alt: 'Shopify', style: {height: '40px'}},
    {src: BMWLogo, alt: 'BMW', style: {height: '72px'}},
    {src: HnMLogo, alt: 'H&M', style: {height: '52px'}},
    {src: HoneywellLogo, alt: 'Honeywell', style: {height: '36px'}},
    {src: EyLogo, alt: 'EY', style: {height: '58px', marginTop: '-16px'}},
    {src: InfosysLogo, alt: 'Infosys', style: {height: '36px'}},
    {src: BBVALogo, alt: 'BBVA', style: {height: '36px'}},
  ]

  return (
    <>
      <div className="position-relative lp-LogoSuite-wrap">
        <LogoSuite hasDivider={false} className="lp-LogoSuite">
          <LogoSuite.Heading visuallyHidden>GitHub Copilot is used by</LogoSuite.Heading>
          <LogoSuite.Logobar marquee marqueeSpeed="slow" data-animation-paused={isLogoSuiteAnimationPaused}>
            {logos.map((logo, index) => (
              // eslint-disable-next-line @eslint-react/no-array-index-key
              <Image key={`logo-${index}`} src={logo.src} alt={logo.alt} aria-label={logo.alt} style={logo.style} />
            ))}
          </LogoSuite.Logobar>
        </LogoSuite>

        <button
          className="lp-Hero-videoPlayerButton PlayButton PlayButton--gray"
          onClick={toggleLogoSuiteAnimationPause}
          aria-pressed={isLogoSuiteAnimationPaused}
          aria-label={logoSuiteAnimationButtonAriaLabel}
          {...analyticsEvent({
            action: logoSuiteAnimationButtonLabel.toLowerCase(),
            tag: 'button',
            context: 'demo_gif',
            location: 'hero',
          })}
          style={{bottom: '14px'}}
        >
          <VideoIcon />
          <span className="sr-only">{logoSuiteAnimationButtonLabel}</span>
        </button>
      </div>
    </>
  )
}

import {useState} from 'react'
import {LogoSuite, Image} from '@primer/react-brand'
import {LOGOS} from './Logos.data'

const COPY = {
  heading: 'GitHub is used by',
}

const PlayIcon = () => (
  <svg width="20" height="20" viewBox="0 0 20 20" fill="none" role="presentation">
    <path
      d="M6.24905 3.69194C5.82218 3.45967 5.30225 3.76868 5.30225 4.25466V15.7452C5.30225 16.2312 5.82218 16.5402 6.24906 16.3079L16.8079 10.5626C17.2538 10.32 17.2538 9.67983 16.8079 9.4372L6.24905 3.69194ZM4.021 4.25466C4.021 2.79672 5.58078 1.86969 6.86142 2.56651L17.4203 8.31176C18.758 9.03966 18.758 10.9602 17.4203 11.6881L6.86143 17.4333C5.58079 18.1301 4.021 17.2031 4.021 15.7452V4.25466Z"
      fill="currentColor"
    />
  </svg>
)

const PauseIcon = () => (
  <svg width="20" height="20" viewBox="0 0 20 20" fill="none" role="presentation">
    <path
      d="M4.66148 2.3125C3.83593 2.3125 3.16669 2.98174 3.16669 3.80729V16.1927C3.16669 17.0183 3.83593 17.6875 4.66148 17.6875H7.65106C8.47662 17.6875 9.14586 17.0183 9.14586 16.1927V3.80729C9.14586 2.98174 8.47662 2.3125 7.65106 2.3125H4.66148ZM4.44794 3.80729C4.44794 3.68936 4.54355 3.59375 4.66148 3.59375H7.65106C7.769 3.59375 7.86461 3.68936 7.86461 3.80729V16.1927C7.86461 16.3106 7.769 16.4062 7.65106 16.4062H4.66148C4.54355 16.4062 4.44794 16.3106 4.44794 16.1927V3.80729ZM12.349 2.3125C11.5235 2.3125 10.8542 2.98174 10.8542 3.80729V16.1927C10.8542 17.0183 11.5235 17.6875 12.349 17.6875H15.3386C16.1642 17.6875 16.8334 17.0183 16.8334 16.1927V3.80729C16.8334 2.98174 16.1642 2.3125 15.3386 2.3125H12.349ZM12.1355 3.80729C12.1355 3.68936 12.2311 3.59375 12.349 3.59375H15.3386C15.4565 3.59375 15.5521 3.68936 15.5521 3.80729V16.1927C15.5521 16.3106 15.4565 16.4062 15.3386 16.4062H12.349C12.2311 16.4062 12.1355 16.3106 12.1355 16.1927V3.80729Z"
      fill="currentColor"
    />
  </svg>
)

export default function Logos() {
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

  return (
    <div className="Logos">
      <LogoSuite className="Logos-logoSuite">
        <LogoSuite.Heading visuallyHidden>{COPY.heading}</LogoSuite.Heading>
        <LogoSuite.Logobar marquee marqueeSpeed="slow" data-animation-paused={isLogoSuiteAnimationPaused}>
          {LOGOS.map((logo, index) => (
            <Image
              // eslint-disable-next-line @eslint-react/no-array-index-key
              key={index}
              src={logo.image}
              alt={logo.alt}
              style={{width: logo.width, height: 'auto'}}
              loading="lazy"
            />
          ))}
        </LogoSuite.Logobar>
      </LogoSuite>

      <button
        className="Logos-playButton PlayButton PlayButton--gray"
        onClick={toggleLogoSuiteAnimationPause}
        aria-pressed={isLogoSuiteAnimationPaused}
        aria-label={logoSuiteAnimationButtonAriaLabel}
      >
        <VideoIcon />
        <span className="sr-only">{logoSuiteAnimationButtonLabel}</span>
      </button>
    </div>
  )
}

import {
  ArrowSwitchIcon,
  BrowserIcon,
  CodeReviewIcon,
  CommentIcon,
  DeviceMobileIcon,
  GraphIcon,
  InfinityIcon,
  LocationIcon,
  MentionIcon,
  MortarBoardIcon,
  PackageIcon,
  PlugIcon,
  PlusCircleIcon,
  ProjectIcon,
  RepoPushIcon,
  RocketIcon,
  ShieldCheckIcon,
  SparkleFillIcon,
  VersionsIcon,
} from '@primer/octicons-react'
import {Box, Button} from '@primer/react-brand'
import {useState} from 'react'

export default function FeatureMarqueeAnimation() {
  const [isTickerAnimationPaused, setIsTickerAnimationPaused] = useState(false)
  const [tickerAnimationButtonLabel, setTickerAnimationButtonLabel] = useState('Pause')
  const [tickerAnimationButtonAriaLabel, setTickerAnimationButtonAriaLabel] = useState(
    'Animation is currently playing. Click to pause.',
  )
  const toggleTickerAnimationPause = () => {
    setIsTickerAnimationPaused(!isTickerAnimationPaused)
    if (isTickerAnimationPaused) {
      setTickerAnimationButtonAriaLabel('Animation is currently playing. Click to pause.')
      setTickerAnimationButtonLabel('Pause')
    } else {
      setTickerAnimationButtonAriaLabel('Animation is paused. Click to play.')
      setTickerAnimationButtonLabel('Play')
    }
  }

  return (
    <div
      className="lp-Features-Ticker"
      role="marquee"
      aria-label="Scrolling ticker of solution categories found in the GitHub Marketplace"
      data-animation-paused={isTickerAnimationPaused}
    >
      <div className="lp-Features-Ticker-row">
        <div className="lp-Features-Ticker-scroll">
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <CommentIcon />
              Chat
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <ProjectIcon />
              Project management
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <SparkleFillIcon />
              Code Quality
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <RocketIcon />
              Deployment
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <InfinityIcon />
              Continuous Integration
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <MortarBoardIcon />
              Learning
            </span>
          </div>
        </div>
        <div className="lp-Features-Ticker-scroll" aria-hidden>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <CommentIcon />
              Chat
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <ProjectIcon />
              Project management
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <SparkleFillIcon />
              Code Quality
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <RocketIcon />
              Deployment
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <InfinityIcon />
              Continuous Integration
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <MortarBoardIcon />
              Learning
            </span>
          </div>
        </div>
      </div>
      <div className="lp-Features-Ticker-row">
        <div className="lp-Features-Ticker-scroll">
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <GraphIcon />
              Monitoring
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <ShieldCheckIcon />
              Security
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <VersionsIcon />
              Testing
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <ArrowSwitchIcon />
              API Management
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <CodeReviewIcon />
              Code review
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <PackageIcon />
              Dependency management
            </span>
          </div>
        </div>
        <div className="lp-Features-Ticker-scroll" aria-hidden>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <GraphIcon />
              Monitoring
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <ShieldCheckIcon />
              Security
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <VersionsIcon />
              Testing
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <ArrowSwitchIcon />
              API Management
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <CodeReviewIcon />
              Code review
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <PackageIcon />
              Dependency management
            </span>
          </div>
        </div>
      </div>
      <div className="lp-Features-Ticker-row">
        <div className="lp-Features-Ticker-scroll">
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <BrowserIcon />
              IDEs
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <LocationIcon />
              Localization
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <DeviceMobileIcon />
              Mobile
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <RepoPushIcon />
              Publishing
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <PlusCircleIcon />
              Recently added
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <MentionIcon />
              Support
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <PlugIcon />
              Utilities
            </span>
          </div>
        </div>
        <div className="lp-Features-Ticker-scroll" aria-hidden>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <BrowserIcon />
              IDEs
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <LocationIcon />
              Localization
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <DeviceMobileIcon />
              Mobile
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <RepoPushIcon />
              Publishing
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <PlusCircleIcon />
              Recently added
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <MentionIcon />
              Support
            </span>
          </div>
          <div className="lp-Features-Ticker-item">
            <span className="lp-Features-Ticker-content">
              <PlugIcon />
              Utilities
            </span>
          </div>
        </div>
      </div>
      <Box paddingBlockStart={12} className="enterprise-LogoSuite-control">
        <Button
          variant="subtle"
          hasArrow={false}
          className="enterprise-LogoSuite-controlButton"
          onClick={toggleTickerAnimationPause}
          aria-pressed={isTickerAnimationPaused}
          aria-label={tickerAnimationButtonAriaLabel}
        >
          {tickerAnimationButtonLabel}
        </Button>
      </Box>
    </div>
  )
}

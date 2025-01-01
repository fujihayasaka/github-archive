import {IconButton, Stack} from '@primer/react'
import {XIcon} from '@primer/octicons-react'
import styles from './OnboardingVideoBanner.module.css'
import {onboardingVideoUrl} from '../../../constants'

export function OnboardingVideoBanner({onDismiss}: {onDismiss: () => void}) {
  return (
    <Stack direction="horizontal" className="border rounded-2 position-relative width-full p-4">
      <Stack className={styles['header-content']}>
        <p className={`${styles['header']} lh-condensed text-wrap-balance`}>Watch the models demo</p>
        <p className="fgColor-muted f4">
          Watch this 3-minute demo reel to learn everything you can do with GitHub Models
        </p>
      </Stack>
      <Stack className="flex-1">
        <a href={onboardingVideoUrl} className={styles['video-banner']} target="_blank" rel="noreferrer">
          <img
            src="/images/modules/github_models/play-button-vector.svg"
            className={styles['play-button']}
            alt="play-button"
          />
          <img
            src="/images/modules/github_models/mockup-bg.png"
            className={styles['mockup-bg']}
            alt="onboarding-video"
          />
        </a>
        <img
          src="/images/modules/github_models/contribution-graph.svg"
          className={styles['contribution-graph']}
          alt=""
        />
      </Stack>
      <div className="d-flex flex-justify-end flex-items-center position-absolute top-0 right-0 p-2">
        <IconButton size="small" variant="invisible" icon={XIcon} aria-label="Close" onClick={onDismiss} />
      </div>
    </Stack>
  )
}

import styles from './Activate.module.css'
import Celebrate from './Celebrate'
import type {CopilotAnimationStateProps} from '../types'

export default function CopilotAnimationActivate({scale = 1, state}: CopilotAnimationStateProps) {
  return (
    <div className={styles.activate} data-animation-state={state}>
      <div className={styles.copilot}>
        <Celebrate scale={scale} state={state} />
      </div>

      <div className={styles.sparkles}>
        {Array.from({length: 10}).map((_, index) => {
          const animationDelay = `${(Math.random() * 0.1 + 0.2).toFixed(2)}s`
          const animationDuration = `${(0.4 + Math.random() * 0.2).toFixed(2)}s`

          return (
            <div
              className={styles.sparkle}
              // eslint-disable-next-line @eslint-react/no-array-index-key
              key={index}
              style={{animationDelay, animationDuration}}
            >
              <div className={styles.sparkleTrail} style={{animationDelay, animationDuration}} />
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width={16 * scale}
                height={16 * scale}
                viewBox="0 0 16 16"
                style={{animationDelay, transform: `scale(${(Math.random() * 0.2 + 0.8).toFixed(2)})`}}
                aria-hidden="true"
              >
                <path d="M7.53 1.282a.5.5 0 0 1 .94 0l.478 1.306a7.492 7.492 0 0 0 4.464 4.464l1.305.478a.5.5 0 0 1 0 .94l-1.305.478a7.492 7.492 0 0 0-4.464 4.464l-.478 1.305a.5.5 0 0 1-.94 0l-.478-1.305a7.492 7.492 0 0 0-4.464-4.464L1.282 8.47a.5.5 0 0 1 0-.94l1.306-.478a7.492 7.492 0 0 0 4.464-4.464Z" />
              </svg>
            </div>
          )
        })}
      </div>
    </div>
  )
}

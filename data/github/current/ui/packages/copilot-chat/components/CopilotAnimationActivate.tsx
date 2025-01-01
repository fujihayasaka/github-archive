import {clsx} from 'clsx'

import Styles from './CopilotAnimationActivate.module.css'
import CopilotAnimationCelebrateSVG from './CopilotAnimationCelebrateSVG'

function CopilotAnimationActivate({stateClass}: {stateClass: string}) {
  return (
    <div className={clsx(Styles['CopilotCelebration'], stateClass)}>
      <div className={Styles['CopilotCelebration__copilot']}>
        <CopilotAnimationCelebrateSVG ariaLabel="Copilot (Activate)" />
      </div>

      <div className={Styles['CopilotCelebration__sparklesWrapper']}>
        {Array.from({length: 10}).map((_, index) => {
          const animationDelay = `${(Math.random() * 0.1 + 0.2).toFixed(2)}s`
          const animationDuration = `${(0.4 + Math.random() * 0.2).toFixed(2)}s`

          return (
            <div
              className={clsx(
                Styles['CopilotCelebration__sparkle'],
                // @ts-expect-error: The generated class name is valid
                Styles[`CopilotCelebration__sparkle--anim-${index + 1}`] as string,
              )}
              // eslint-disable-next-line @eslint-react/no-array-index-key
              key={index}
              style={{animationDelay, animationDuration}}
            >
              <div className={Styles['CopilotCelebration__sparkleTrail']} style={{animationDelay, animationDuration}} />
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 16 16"
                width="16"
                height="16"
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

export default CopilotAnimationActivate

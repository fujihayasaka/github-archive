import {LogIcon, SparkleFillIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'
import {clsx} from 'clsx'
import {useEffect, useState} from 'react'

import {useErrors} from '../../contexts/ErrorsContext'
import {useWorkbench} from '../../hooks/use-workbench'
import {fixAllPrompt, generateErrorsPrompt} from '../../utilities/error'
import {ErrorDisplay} from '../ErrorDisplay'
import styles from './ErrorOverlay.module.css'

interface ErrorOverlayProps {
  isFetching: boolean
}

export function ErrorOverlay({isFetching}: ErrorOverlayProps) {
  const {overlayErrors} = useErrors()
  const {submitPrompt} = useWorkbench()
  const firstError = overlayErrors[0]

  const [isVisible, setIsVisible] = useState(false)
  useEffect(() => {
    if (!isFetching && overlayErrors.length > 0) {
      setIsVisible(true)
    } else {
      setIsVisible(false)
    }
  }, [overlayErrors, isFetching])

  return (
    <div className={isVisible ? clsx(styles.motion, styles.motionVisible) : clsx(styles.motion)}>
      <div className={styles.errorContent}>
        <Blankslate>
          <Blankslate.Visual>
            <LogIcon size={32} />
          </Blankslate.Visual>
          <Blankslate.Heading>
            <span className={styles.label}>Hm, something went wrong</span>
          </Blankslate.Heading>
          {firstError && (
            <>
              <Blankslate.Description>
                <ErrorDisplay error={firstError} showSource />
              </Blankslate.Description>
              {submitPrompt && (
                <Button
                  variant="primary"
                  leadingVisual={SparkleFillIcon}
                  onClick={() => {
                    submitPrompt(generateErrorsPrompt(fixAllPrompt, [firstError.messageRaw]), 'refine', 'autofix')
                  }}
                  className="mt-3"
                >
                  Autofix error
                </Button>
              )}
            </>
          )}
        </Blankslate>
      </div>
    </div>
  )
}

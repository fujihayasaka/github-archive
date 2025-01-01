import {testIdProps} from '@github-ui/test-id-props'
import {Button} from '@primer/react'

import {BlankslateErrorMessage} from '../../../components/error-boundaries/blankslate-error-message'
import styles from './settings-error-fallback.module.css'

const clickHandler = () => {
  window.location.reload()
}

export const SettingsErrorFallback: React.FC = () => {
  return (
    <BlankslateErrorMessage
      as="main"
      headingAs="h2"
      heading="This page failed to load"
      content="Sorry about that. Please try refreshing and contact us if the problem persists."
      {...testIdProps('project-settings-error-fallback')}
    >
      <Button variant="primary" onClick={clickHandler} className={styles.Button}>
        Reload
      </Button>
    </BlankslateErrorMessage>
  )
}

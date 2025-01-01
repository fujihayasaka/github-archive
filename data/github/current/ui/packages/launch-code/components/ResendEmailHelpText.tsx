import {useEffect, useRef} from 'react'
import {announceFromElement} from '@github-ui/aria-live'
import {testIdProps} from '@github-ui/test-id-props'
import {CheckCircleIcon} from '@primer/octicons-react'
import {Box, InlineLink, Text} from '@primer/react-brand'

import styles from './ResendEmailHelpText.module.css'

interface ResendEmailHelpTextProps {
  handleResendLaunchCodeEmail: () => void
  emailResent: boolean
  updateEmailPath: string
}

export const ResendEmailHelpText = ({
  emailResent,
  handleResendLaunchCodeEmail,
  updateEmailPath,
}: ResendEmailHelpTextProps) => {
  const announceRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (emailResent && announceRef.current) announceFromElement(announceRef.current)
  }, [emailResent])

  return (
    <div>
      <Text variant="muted">
        {"Didn't get your email? "}
        <button type="button" className={styles.resendButton} onClick={handleResendLaunchCodeEmail}>
          Resend the code
        </button>{' '}
        or <InlineLink href={updateEmailPath}>update your email address</InlineLink>.
      </Text>
      <Box paddingBlockStart="condensed">
        {emailResent && (
          <div {...testIdProps('resend-email-success-message')} className={styles.resentSuccessContainer}>
            <CheckCircleIcon size={16} className={styles.resentSuccessIcon} />
            <div role="status" className={styles.resentText} ref={announceRef}>
              Email was resent
            </div>
          </div>
        )}
      </Box>
    </div>
  )
}

import {useEffect, useRef, useState} from 'react'
import {testIdProps} from '@github-ui/test-id-props'
import {useAnalytics} from '@github-ui/use-analytics'
import {Box, Button, Heading, Stack, Text} from '@primer/react-brand'
import {DevHelpText} from './components/DevHelpText'
import {ResendEmailHelpText} from './components/ResendEmailHelpText'
import {TermsOfService} from './components/TermsOfService'
import {handleKeyInput} from './helpers/handle-key-input'
import {handleKeyNavigation} from './helpers/handle-key-navigation'
import {handlePaste} from './helpers/handle-paste'
import {handleResendEmail} from './helpers/handle-resend-email'
import {handleSubmit} from './helpers/handle-submit'
import type {HiddenFieldsParams} from './helpers/url-encoded-request-body'

import styles from './LaunchCode.module.css'

export interface LaunchCodeProps {
  email: string | null
  error?: string
  isDevEnv: boolean
  launchCodeLength: number
  showLaunchCode: boolean
  verificationToken: number | null
  hiddenFieldsParams: HiddenFieldsParams
  resendVerificationPath: string
  updateEmailPath: string
}

export function LaunchCode({
  email,
  isDevEnv,
  launchCodeLength,
  showLaunchCode,
  verificationToken,
  hiddenFieldsParams,
  resendVerificationPath,
  updateEmailPath,
}: LaunchCodeProps) {
  const {sendAnalyticsEvent} = useAnalytics()
  const [errorMessage, setErrorMessage] = useState<string>('')
  const inputRefs = useRef<HTMLInputElement[]>([])
  const [submittingForm, setSubmittingForm] = useState(false)
  const [emailResent, setEmailResent] = useState(false)

  const handleFormSubmit = () => {
    handleSubmit({hiddenFieldsParams, inputRefs, setErrorMessage, setSubmittingForm})
  }

  const handleResendLaunchCodeEmail = () => {
    handleResendEmail({resendVerificationPath, sendAnalyticsEvent, setEmailResent})
  }

  useEffect(() => {
    // Focus on the first input when the component mounts
    if (inputRefs.current && inputRefs.current[0]) {
      inputRefs.current[0].focus()
    }
  }, [])

  return (
    <Stack direction="vertical" justifyContent={'space-between'} padding="condensed" className={styles.container}>
      <Box>
        {showLaunchCode ? (
          <form
            onSubmit={e => {
              e.preventDefault()
              handleFormSubmit()
            }}
            data-target="launch-code.form"
          >
            <input type="hidden" name="return_to" value={hiddenFieldsParams?.return_to ?? ''} />
            <fieldset>
              <legend>
                <Heading as="h2" size="6" weight="semibold">
                  Confirm your email address
                </Heading>
                {email && (
                  <>
                    <Box paddingBlockStart="condensed" paddingBlockEnd="condensed">
                      <Text as="p" size="200" variant="muted">
                        We have sent a code to <span className="text-bold">{email}</span>
                      </Text>
                    </Box>
                    <Text as="p" size="200" variant="muted" weight="semibold">
                      Enter code
                    </Text>
                  </>
                )}
              </legend>
              <Box marginBlockStart="condensed" marginBlockEnd="condensed">
                <Stack
                  direction="horizontal"
                  gap={4}
                  justifyContent="space-between"
                  padding="none"
                  className="width-full"
                >
                  {Array.from({length: launchCodeLength}, (_, index) => (
                    <div key={index}>
                      <label id={`launch-code-label-${index}`} key={index} className="sr-only">
                        {`Digit ${index + 1} of the launch code`}
                      </label>
                      <input
                        id={`launch-code-${index}`}
                        {...testIdProps(`launch-code-${index}`)}
                        ref={el => {
                          if (el) inputRefs.current[index] = el
                        }}
                        className={styles.input}
                        type="number"
                        aria-labelledby={`launch-code-label-${index}`}
                        autoComplete="off"
                        autoCapitalize="off"
                        spellCheck="false"
                        name="launch_code[]"
                        maxLength={1}
                        size={1}
                        onPaste={event => handlePaste({event, inputRefs, handleFormSubmit})}
                        onKeyDown={event => handleKeyNavigation(event, inputRefs)}
                        onInput={event => {
                          handleKeyInput({event, inputRefs, handleFormSubmit})
                        }}
                        required
                      />
                    </div>
                  ))}
                </Stack>
              </Box>
            </fieldset>

            <Box marginBlockEnd="condensed">
              {errorMessage && (
                <Text as="p" size="200" variant="muted" {...testIdProps('launch-code-error-message')}>
                  {errorMessage}
                </Text>
              )}
            </Box>
            <Box>
              <Button className="width-full" variant="primary" disabled={submittingForm}>
                Continue
              </Button>
            </Box>
          </form>
        ) : null}
        <Box marginBlockStart="normal">
          <ResendEmailHelpText
            handleResendLaunchCodeEmail={handleResendLaunchCodeEmail}
            emailResent={emailResent}
            updateEmailPath={updateEmailPath}
          />
        </Box>
        {isDevEnv && email && <DevHelpText verificationToken={verificationToken} />}
      </Box>
      <TermsOfService />
    </Stack>
  )
}

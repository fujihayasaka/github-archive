import {useRef} from 'react'
import {Box, Button, Heading, Text} from '@primer/react-brand'
import {handlePaste} from './helpers/handle-paste'
import {handleKeyNavigation} from './helpers/handle-key-navigation'
import {handleKeyInput} from './helpers/handle-key-input'
import {TermsOfService} from './components/TermsOfService'

export interface LaunchCodeProps {
  email: string | null
  error?: string
  isDevEnv: boolean
  launchCodeLength: number
  showLaunchCode: boolean
  verificationToken: number | null
}

export function LaunchCode({
  email,
  error,
  isDevEnv,
  launchCodeLength,
  showLaunchCode,
  verificationToken,
}: LaunchCodeProps) {
  const inputRefs = useRef<HTMLInputElement[]>([])

  const launchCodeInputs = Array.from({length: launchCodeLength}, (_, index) => (
    <div key={index}>
      <label key={index} htmlFor={`launch-code-${index}`} className="sr-only">
        Digit {index + 1} of the launch code
      </label>
      <input
        ref={el => {
          if (el) inputRefs.current[index] = el
        }}
        id={`launch-code-${index}`}
        type="number"
        autoComplete="off"
        autoCapitalize="off"
        spellCheck="false"
        name="launch_code[]"
        maxLength={1}
        size={1}
        onPaste={event => handlePaste(event, inputRefs)}
        onKeyDown={event => handleKeyNavigation(event, inputRefs)}
        onInput={event => handleKeyInput(event, inputRefs)}
        required
      />
    </div>
  ))

  const handleSubmit = () => {
    // TODO: Submit the form
  }

  return (
    <Box>
      {showLaunchCode ? (
        <form onSubmit={handleSubmit} data-target="launch-code.form">
          {/* TODO: Add Hidden Fields on form submit */}
          <fieldset>
            <legend>
              <Heading as="h2" size="5">
                Confirm your email address
              </Heading>
              {email && (
                <>
                  <Box>
                    <Text>We have sent a code to {email}</Text>
                  </Box>
                  <Text>Enter code</Text>
                </>
              )}
            </legend>
            <Box>{launchCodeInputs}</Box>
          </fieldset>

          {/* TODO: Update this to Primer Brand element */}
          <div role="alert">
            {/* TODO: Add proper error messaging. Check on error type and structure */}
            {error && <div>Error message: {error?.toString()}</div>}
          </div>

          {/* TODO: Submit form */}
          <Button variant="primary">Continue</Button>
        </form>
      ) : null}

      <Box>
        {isDevEnv && email && (
          <div>
            Psst, Hubber:
            {verificationToken ? (
              <div>
                In local development, you can use this launch code to verify your email:
                <span>{verificationToken}</span>
              </div>
            ) : (
              <div>
                If you wait a second and reload this page, you should see the launch code to verify your email address
                in local development.
              </div>
            )}
          </div>
        )}
      </Box>
      <TermsOfService />
    </Box>
  )
}

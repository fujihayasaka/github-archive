import {testIdProps} from '@github-ui/test-id-props'
import {Link} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {JSON_SCHEMA_DOCS_URL} from './constants'

export type PlaygroundErrorProps = {
  message: string
  showResetButton: boolean
  handleClearHistory: () => void
}

export const jsonFormatErrorMessage =
  "'messages' must contain the word 'json' in some form, to use 'response_format' of type 'json_object'."
export const jsonSchemaFormatErrorMessage = "parameter: 'response_format.json_schema"
export const rateLimitedMessage = 'Rate limited, please try again later.'
export const rateLimitDocsUrl = 'https://docs.github.com/github-models/prototyping-with-ai-models#rate-limits'

export function PlaygroundError({message, showResetButton, handleClearHistory}: PlaygroundErrorProps) {
  let messageContent = <>{message}</>

  if (message === rateLimitedMessage) {
    messageContent = (
      <>
        <div />
        Sorry, you’re currently hitting{' '}
        <Link href={rateLimitDocsUrl} inline>
          usage rate limits
        </Link>
        .
      </>
    )
  } else if (message === jsonFormatErrorMessage) {
    messageContent = (
      <>
        <div />
        Please adjust your input message or system prompt to include the word &apos;<strong>JSON</strong>&apos; for this
        response output format.
      </>
    )
  } else if (message.includes(jsonSchemaFormatErrorMessage)) {
    messageContent = (
      <>
        <div />
        Please adjust your JSON schema to address ${message} Check the{' '}
        <Link href={JSON_SCHEMA_DOCS_URL} inline>
          OpenAI guides{' '}
        </Link>
        on structuring your JSON schema correctly to generate outputs.
      </>
    )
  }

  return (
    <div {...testIdProps('playground-error')} className="py-2">
      <Banner
        variant="warning"
        title="Chat error message"
        hideTitle
        description={messageContent}
        primaryAction={
          showResetButton && <Banner.PrimaryAction onClick={handleClearHistory}>Reset chat</Banner.PrimaryAction>
        }
      />
    </div>
  )
}

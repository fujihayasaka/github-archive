import {testIdProps} from '@github-ui/test-id-props'
import {Flash, Link} from '@primer/react'

export type CompletionErrorProps = {
  message: string
}

export const jsonFormatErrorMessage =
  "'messages' must contain the word 'json' in some form, to use 'response_format' of type 'json_object'."
export const jsonSchemaFormatErrorMessage = "parameter: 'response_format.json_schema"
export const rateLimitedMessage = 'Rate limited, please try again later.'
export const rateLimitDocsUrl = 'https://docs.github.com/github-models/prototyping-with-ai-models#rate-limits'

export function CompletionError({message}: CompletionErrorProps) {
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
  }

  return (
    <div className="py-2" {...testIdProps('completion-error')}>
      <Flash variant="warning">{messageContent}</Flash>
    </div>
  )
}

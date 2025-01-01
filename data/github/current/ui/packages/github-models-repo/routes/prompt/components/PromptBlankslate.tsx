import {StackIcon} from '@primer/octicons-react'
import {Blankslate} from '@primer/react/experimental'
import styles from './PromptBlankslate.module.css'

export function PromptBlankslate() {
  return (
    <div className={styles.blankSlate}>
      <Blankslate>
        <Blankslate.Visual>
          <StackIcon size="medium" />
        </Blankslate.Visual>
        <Blankslate.Heading>Iterate on your prompt</Blankslate.Heading>
        <Blankslate.Description>
          Use the prompt editor to run a single prompt repeatedly, refining it and adjusting your{' '}
          <code>{'{{variables}}'}</code> to achieve the perfect response.
        </Blankslate.Description>
      </Blankslate>
    </div>
  )
}

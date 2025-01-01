import {FormControl} from '@primer/react'
import type {Meta, StoryFn} from '@storybook/react'
import {useId, useState} from 'react'

import type {CommandEvent} from '../command-event'
import {CommandKeybindingHint} from './CommandKeybindingHint'
import {GlobalCommands} from './GlobalCommands'
import styles from './GlobalCommands.stories.module.css'

export default {
  title: 'Utilities/ui-commands/GlobalCommands',
  component: GlobalCommands,
  parameters: {},
  argTypes: {},
} satisfies Meta<typeof GlobalCommands>

export const GlobalCommandsExample: StoryFn = () => {
  const [output, setOutput] = useState('')

  const handleCommand = (event: CommandEvent) => setOutput(JSON.stringify(event))

  const outputId = useId()

  return (
    <>
      <GlobalCommands commands={{'github:submit-form': handleCommand}} />
      <p>
        Try pressing <CommandKeybindingHint commandId="github:submit-form" format="full" /> to trigger a command.
      </p>
      {output && (
        <FormControl id={outputId}>
          <FormControl.Label className={styles.FormControl_Label}>Received command event</FormControl.Label>
          <output id={outputId} className={styles.Box}>
            {output}
          </output>
        </FormControl>
      )}
    </>
  )
}
GlobalCommandsExample.storyName = 'GlobalCommands'

import {FormControl, Textarea} from '@primer/react'
import type {Meta, StoryFn} from '@storybook/react'
import {useId, useState} from 'react'

import type {CommandEvent} from '../command-event'
import {CommandKeybindingHint} from './CommandKeybindingHint'
import {ScopedCommands} from './ScopedCommands'
import styles from './ScopedCommands.stories.module.css'

export default {
  title: 'Utilities/ui-commands/ScopedCommands',
  component: ScopedCommands,
  parameters: {},
  argTypes: {},
} satisfies Meta<typeof ScopedCommands>

export const ScopedCommandsExample: StoryFn = () => {
  const [output, setOutput] = useState('')

  const handleCommand = (event: CommandEvent) => setOutput(JSON.stringify(event))

  const outputId = useId()

  return (
    <>
      <ScopedCommands commands={{'github:submit-form': handleCommand}}>
        <FormControl>
          <FormControl.Label>In-scope input</FormControl.Label>
          <FormControl.Caption>
            Try focusing and pressing <CommandKeybindingHint commandId="github:submit-form" format="full" /> to trigger
            a command.
          </FormControl.Caption>
          <Textarea />
        </FormControl>
      </ScopedCommands>
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
ScopedCommandsExample.storyName = 'ScopedCommands'

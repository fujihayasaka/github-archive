import {Dialog, FormControl, Stack, Textarea} from '@primer/react'
import {useRef} from 'react'

import {useTerminalContext} from '../contexts/TerminalContext'
import {useAnalytics} from '../telemetry/use-analytics'

interface ITerminalConfigurationPanel {
  close: () => void
  returnFocusRef?: React.RefObject<HTMLElement>
}

export function TerminalConfigurationPanel({close, returnFocusRef}: ITerminalConfigurationPanel): JSX.Element {
  const {
    state: {tasks},
    dispatch,
  } = useTerminalContext()

  const sendEvent = useAnalytics()

  const newBuildCommand = useRef<string | undefined>(tasks.build)
  const newRunCommand = useRef<string | undefined>(tasks.run)
  const newTestCommand = useRef<string | undefined>(tasks.test)

  const save = async () => {
    // Use undefined instead of empty string
    const newTasks = {
      build: newBuildCommand.current || undefined,
      run: newRunCommand.current || undefined,
      test: newTestCommand.current || undefined,
    }

    dispatch({type: 'SET_TASKS', tasks: newTasks})
    sendEvent('validation.configure.saved', {
      hasBuildCommand: !!newTasks.build,
      hasRunCommand: !!newTasks.run,
      hasTestCommand: !!newTasks.test,
    })
    close()
  }

  const dismiss = () => {
    sendEvent('validation.configure.dismissed', {
      hasBuildCommand: !!tasks.build,
      hasRunCommand: !!tasks.run,
      hasTestCommand: !!tasks.test,
    })
    close()
  }

  return (
    <Dialog
      width="large"
      title="Configure commands"
      onClose={dismiss}
      returnFocusRef={returnFocusRef}
      footerButtons={[
        {
          buttonType: 'default',
          content: 'Cancel',
          onClick: dismiss,
        },
        {
          buttonType: 'primary',
          content: 'Save',
          onClick: save,
        },
      ]}
    >
      <Stack direction="vertical" spacing="normal">
        <FormControl>
          <FormControl.Label>Build</FormControl.Label>
          <Textarea
            block
            rows={2}
            resize="vertical"
            // eslint-disable-next-line react-compiler/react-compiler
            defaultValue={newBuildCommand.current}
            onChange={event => (newBuildCommand.current = event.target.value)}
          />
          <FormControl.Caption>The command used to build your application, e.g. npm run build</FormControl.Caption>
        </FormControl>
        <FormControl>
          <FormControl.Label>Run</FormControl.Label>
          <Textarea
            block
            rows={2}
            resize="vertical"
            // eslint-disable-next-line react-compiler/react-compiler
            defaultValue={newRunCommand.current}
            onChange={event => (newRunCommand.current = event.target.value)}
          />
          <FormControl.Caption>The command used to run your application, e.g. npm run start</FormControl.Caption>
        </FormControl>
        <FormControl>
          <FormControl.Label>Test</FormControl.Label>
          <Textarea
            block
            rows={2}
            resize="vertical"
            // eslint-disable-next-line react-compiler/react-compiler
            defaultValue={newTestCommand.current}
            onChange={event => (newTestCommand.current = event.target.value)}
          />
          <FormControl.Caption>The command used to test your application, e.g. npm run test</FormControl.Caption>
        </FormControl>
      </Stack>
    </Dialog>
  )
}

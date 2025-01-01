import {Button, FormControl, Stack, TextInput} from '@primer/react'
import {useState} from 'react'

export function ClientError() {
  const [message, setMessage] = useState('This is a client error!')
  return (
    <Stack direction="horizontal">
      <Stack className="m-2">
        <FormControl>
          <FormControl.Label>Custom error message</FormControl.Label>
          <TextInput value={message} onChange={e => setMessage(e.target.value)} placeholder="Enter error message" />
        </FormControl>
      </Stack>
      <Button
        className="m-2"
        onClick={() => {
          throw new Error(message)
        }}
      >
        Throw client error
      </Button>
    </Stack>
  )
}

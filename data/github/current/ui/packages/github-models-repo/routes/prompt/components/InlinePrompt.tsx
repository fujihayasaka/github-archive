import {Label, Stack} from '@primer/react'
import type {PromptConfig} from '../prompts'
import ModelName from './ModelName'

export interface InlinePromptProps {
  prompt: PromptConfig
  renderActions: () => JSX.Element
}

export function InlinePrompt({prompt, renderActions}: InlinePromptProps) {
  return (
    <>
      <Stack className="width-full" direction="vertical" align="stretch">
        <Stack direction="horizontal" gap="none">
          <Stack.Item grow>
            <ModelName modelId={prompt.model} />
          </Stack.Item>

          {renderActions()}
        </Stack>
        <div>
          {prompt.messages &&
            prompt.messages.map((msg, i) => {
              if (!msg.message) {
                return null
              }

              return (
                // Ignoring the eslint rule here because it's in combination with the timestamp as a key
                // eslint-disable-next-line @eslint-react/no-array-index-key
                <div key={`${i}-${msg.timestamp.toString()}`}>
                  <Label className="color-fg-muted">{msg.role}</Label>
                  <br />
                  {msg.message}
                </div>
              )
            })}
        </div>
      </Stack>
    </>
  )
}

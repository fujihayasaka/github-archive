import {Label, Stack, useResponsiveValue} from '@primer/react'
import type {PromptConfig} from '../prompts'
import ModelName from './ModelName'
import {useModels} from '../contexts/ModelsContext'
import {findModel} from '../models'
import {useCallback, type PropsWithChildren} from 'react'
import type {RepoModel} from '../../../types'
import ModelPicker from './ModelPicker'

export interface InlinePromptProps extends PropsWithChildren {
  prompt: PromptConfig
  promptIndex: number
  onModelSelect?: (model: RepoModel, promptIndex: number) => void
}

export function InlinePrompt({children, onModelSelect, prompt, promptIndex}: InlinePromptProps) {
  const models = useModels()
  const modelId = prompt.model
  const model = modelId ? findModel(modelId, models) : undefined
  const isMobile = useResponsiveValue({narrow: true}, false)
  const canSelectModel = !isMobile && onModelSelect !== undefined
  const handleModelSelect = useCallback(
    (newModel: RepoModel) => {
      if (onModelSelect) onModelSelect(newModel, promptIndex)
    },
    [onModelSelect, promptIndex],
  )
  const supportsSystemPrompt = model?.capabilities?.systemPrompt ?? false

  return (
    <Stack className="width-full" direction="vertical" align="stretch">
      <Stack
        direction={{narrow: 'vertical', regular: 'horizontal'}}
        gap={{narrow: 'condensed', regular: 'none'}}
        align={{narrow: 'start', regular: 'center'}}
      >
        <Stack.Item grow className="width-full d-flex">
          {canSelectModel ? (
            <ModelPicker
              buttonProps={{variant: 'invisible', className: 'px-1', size: 'small'}}
              selectedModel={model}
              onSelect={handleModelSelect}
            />
          ) : (
            <ModelName modelId={modelId} />
          )}
        </Stack.Item>

        {children}
      </Stack>
      <Stack gap="normal">
        {prompt.messages &&
          prompt.messages.map((msg, i) => {
            // Don't render the system prompt if the model doesn't support it. We still have to keep it in the prompt
            // so that the prompt can be forked with a different model (that might support a system prompt)
            if (msg.role === 'system' && !supportsSystemPrompt) {
              return null
            }

            return (
              <Message key={`${i}-${msg.timestamp.toString()}`} role={msg.role}>
                {msg.message ? <>{msg.message}</> : <span className="fgColor-muted">Add prompt</span>}
              </Message>
            )
          })}
      </Stack>
    </Stack>
  )
}

function Message({role, children}: PropsWithChildren<{role: string}>) {
  return (
    <Stack gap="condensed">
      <div>
        <Label className="fgColor-muted">{role}</Label>
      </div>
      {children}
    </Stack>
  )
}

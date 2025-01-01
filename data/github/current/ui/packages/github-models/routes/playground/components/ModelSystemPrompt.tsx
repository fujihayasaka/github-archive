import {FormControl, Textarea} from '@primer/react'
import {ImprovePrompt} from './ImprovePrompt'

export function ModelSystemPrompt({
  systemPrompt,
  handleSystemPromptChange,
  updateSystemPrompt,
  onSinglePlaygroundView,
  label,
}: {
  systemPrompt: string
  handleSystemPromptChange: (event: React.ChangeEvent<HTMLTextAreaElement>) => void
  updateSystemPrompt: (systemPrompt: string) => void
  onSinglePlaygroundView?: boolean
  label?: string
  showPresets?: boolean
}) {
  return (
    <FormControl>
      <FormControl.Label className="d-flex flex-justify-between flex-items-end width-full">
        {label || 'System prompt'}
        {onSinglePlaygroundView && <ImprovePrompt prompt={systemPrompt} handleUpdatePrompt={updateSystemPrompt} />}
      </FormControl.Label>
      <Textarea
        value={systemPrompt}
        block
        resize="vertical"
        rows={4}
        onChange={handleSystemPromptChange}
        name="systemPrompt"
        placeholder="Define the model's behavior or role. Example: 'You are a spaceship captain telling intergalactic tales.'"
      />
    </FormControl>
  )
}

import {testIdProps} from '@github-ui/test-id-props'
import React, {useState} from 'react'
import {Checkbox, CheckboxGroup, FormControl, TextInput} from '@primer/react'
import {Banner, Dialog} from '@primer/react/experimental'
import {useClickAnalytics} from '@github-ui/use-analytics'

import type {Preset} from '../../../../types'
import {Panel} from '../../../../utils/playground-manager'
import {usePlaygroundState} from '../../../../contexts/PlaygroundStateContext'
import {createPreset, getTextFromMessage, isValidString, updatePreset} from '../../../../utils/presets'

export const NAME_MAX_SIZE = 100
export const INPUT_VALUE = {
  none: 'none',
  chatInput: 'chatInput',
  firstMessage: 'firstMessage',
}

export interface PresetDialogProps {
  onClose: () => void
  onSuccess: (urlIdentifier: string) => void
  selectedPreset: Preset
  action: 'create' | 'update'
}

export function PresetDialog({onClose, onSuccess, selectedPreset, action}: PresetDialogProps) {
  const {sendClickAnalyticsEvent} = useClickAnalytics()
  const playgroundState = usePlaygroundState()
  const mainModel = playgroundState.models[Panel.Main]

  const systemPrompt = mainModel?.systemPrompt || ''
  const firstMessage = getTextFromMessage(mainModel?.messages[0]?.message) || ''
  const chatInput = getTextFromMessage(mainModel?.chatInput) || ''

  const isCreate = action === 'create'
  const [name, setName] = useState<string>(isCreate ? '' : selectedPreset.name)
  const [isPublic, setIsPublic] = useState<boolean>(isCreate ? false : !selectedPreset.private)
  const [useSystemPrompt, setUseSystemPrompt] = useState<boolean>(systemPrompt !== '')
  const [useFirstMessage, setUseFirstMessage] = useState<boolean>(false)
  const [useChatInput, setUseChatInput] = useState<boolean>(false)

  const [saveError, setSaveError] = useState<string | null>(null)
  const [nameError, setNameError] = useState<string | null>(null)
  const nameInputRef = React.useRef<HTMLInputElement>(null)

  const setErrorFromBackend = (error: {error?: string; name?: string[]; url_identifier?: string}) => {
    if (error.error) setSaveError(error.error)
    if (error.url_identifier) setNameError(`Name ${error.url_identifier}`)
    if (error.name) setNameError(`Name ${error.name.join(', ')}`)
    nameInputRef.current?.focus()
  }

  const onSubmit = async (event: React.FormEvent) => {
    event.preventDefault()

    // Validation
    setNameError(null)

    if (!isValidString(name)) {
      setNameError('Name is required')
      nameInputRef.current?.focus()
      return
    }
    if (name.trim().length > NAME_MAX_SIZE) {
      setNameError(`Name cannot be longer than ${NAME_MAX_SIZE} characters`)
      nameInputRef.current?.focus()
      return
    }

    // Save preset
    try {
      const {urlIdentifier} = selectedPreset

      const system_prompt = useSystemPrompt ? systemPrompt : ''
      const separator = useFirstMessage && useChatInput ? '\n' : ''
      const chat_prompt = `${useFirstMessage ? firstMessage : ''}${separator}${useChatInput ? chatInput : ''}`

      const preset = {
        name,
        private: !isPublic,
        parameters: {system_prompt, chat_prompt},
      }

      const res = isCreate ? await createPreset({preset}) : await updatePreset({urlIdentifier, preset})

      if (res.ok) {
        const resPreset = await res.json()
        onSuccess(resPreset.urlIdentifier)
        sendClickAnalyticsEvent({
          category: 'github_models_playground',
          action: 'click_to_save_preset',
          label: 'ref_cta:save_preset_dialog;ref_loc:presets_dialog',
        })
        onClose()
      } else {
        const body = await res.json()
        setErrorFromBackend(body.error)
      }
    } catch {
      setErrorFromBackend({error: `Failed to ${action} preset: ${name}`})
    }
  }

  return (
    <Dialog
      title={
        <div {...testIdProps('save-preset-dialog')} className="capitalize">{`${
          isCreate ? 'Create' : 'Update'
        } prompt`}</div>
      }
      width="large"
      onClose={() => {
        onClose()
        sendClickAnalyticsEvent({
          category: 'github_models_playground',
          action: 'click_to_close_preset_dialog',
          label: 'ref_cta:close_preset_dialog;ref_loc:presets_dialog',
        })
      }}
      footerButtons={[
        {
          buttonType: 'default',
          content: 'Cancel',
          onClick: onClose,
          form: 'preset-dialog-form',
        },
        {
          buttonType: 'primary',
          content: isCreate ? 'Save prompt' : 'Update prompt',
          form: 'preset-dialog-form',
          type: 'submit',
        },
      ]}
    >
      {saveError && (
        <Banner
          hideTitle
          variant="critical"
          title="Something went wrong"
          description={saveError}
          className="mb-3"
          {...testIdProps('generic-error-banner')}
        />
      )}

      <form onSubmit={onSubmit} id="preset-dialog-form">
        <FormControl id="preset-name-input" className="mb-3" required>
          <FormControl.Label>Name</FormControl.Label>
          <TextInput
            name="name"
            onChange={e => setName(e.target.value)}
            placeholder=""
            value={name}
            validationStatus={nameError ? 'error' : undefined}
            ref={nameInputRef}
            className="width-full"
          />
          {nameError ? <FormControl.Validation variant="error">{nameError}</FormControl.Validation> : null}
        </FormControl>
        <CheckboxGroup className="mb-3">
          <CheckboxGroup.Label>Included fields</CheckboxGroup.Label>
          <CheckboxGroup.Caption>
            Select the fields you want to include in your preset. If both &quot;Current input&quot; and &quot;First
            message&quot; are checked, they will be combined into the chat prompt.
          </CheckboxGroup.Caption>
          {isValidString(systemPrompt) && (
            <FormControl>
              <Checkbox checked={useSystemPrompt} onChange={() => setUseSystemPrompt(!useSystemPrompt)} />
              <FormControl.Label>System prompt</FormControl.Label>
            </FormControl>
          )}
          {isValidString(chatInput) && (
            <FormControl>
              <Checkbox checked={useChatInput} onChange={() => setUseChatInput(!useChatInput)} />
              <FormControl.Label>Current input</FormControl.Label>
              <FormControl.Caption>The current unsent chat input will be saved.</FormControl.Caption>
            </FormControl>
          )}
          {isValidString(firstMessage) && (
            <FormControl>
              <Checkbox checked={useFirstMessage} onChange={() => setUseFirstMessage(!useFirstMessage)} />
              <FormControl.Label>First message</FormControl.Label>
              <FormControl.Caption>The first message sent by the user this session will be saved.</FormControl.Caption>
            </FormControl>
          )}
        </CheckboxGroup>
        <CheckboxGroup>
          <CheckboxGroup.Label>Settings</CheckboxGroup.Label>
          <FormControl id="preset-public-checkbox">
            <Checkbox name="public" checked={isPublic} onChange={() => setIsPublic(!isPublic)} />
            <FormControl.Label>Enable sharing</FormControl.Label>
            <FormControl.Caption>
              Anyone with the URL will be able to view and use this prompt, but not edit. Prompts are private by
              default.
            </FormControl.Caption>
          </FormControl>
        </CheckboxGroup>
      </form>
    </Dialog>
  )
}

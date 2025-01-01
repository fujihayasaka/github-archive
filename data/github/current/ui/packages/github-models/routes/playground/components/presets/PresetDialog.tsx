import {testIdProps} from '@github-ui/test-id-props'
import React, {type FormEvent, useEffect, useState} from 'react'
import {Checkbox, FormControl, TextInput} from '@primer/react'
import {Banner, Dialog} from '@primer/react/experimental'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

import type {Preset} from '../../../../types'
import {Panel} from '../../../../utils/playground-manager'
import {usePlaygroundState} from '../../../../contexts/PlaygroundStateContext'

export const NAME_MAX_SIZE = 100
export const DESCRIPTION_MAX_SIZE = 255

export interface PresetDialogProps {
  onClose: () => void
  onSubmit: (presetData: Preset) => void
  selectedPreset: Preset | null
  action: 'create' | 'update'
  errors?: {name?: string[]; conversation_history?: string; url_identifier?: string; error?: string} | null
}

export function PresetDialog({onClose, onSubmit, selectedPreset, action, errors}: PresetDialogProps) {
  const playgroundState = usePlaygroundState()

  const [nameError, setNameError] = useState<string | null>(null)
  const [descriptionError, setDescriptionError] = useState<string | null>(null)
  const [conversationHistoryError, setConversationHistoryError] = useState<string | null>(null)

  const isCreate = action === 'create'
  const dialogTitle = isCreate ? 'Create new preset' : 'Edit preset'

  const mainModel = playgroundState.models[Panel.Main]

  const systemPrompt = mainModel?.systemPrompt

  const playgroundParameters = {
    ...mainModel?.parameters,
    ...(systemPrompt && systemPrompt.trim() !== '' && {system_prompt: systemPrompt}), // Only send in the system prompt if it's not empty
    response_format: mainModel?.responseFormat || 'text',
  }

  const shouldSaveImages = useFeatureFlag('project_neutron_presets_allow_images')

  const chatHistoryRaw = mainModel?.messages || []
  const chatHistory = shouldSaveImages
    ? chatHistoryRaw
    : chatHistoryRaw.flatMap(item => {
        if (typeof item.message === 'string') {
          return [item]
        }

        // Get ONLY the textual message, and set that as the message. This removes anything else, which right now is images
        // which is what we want to achieve.
        const newMessage = item.message.find(i => i.type === 'text')
        if (newMessage != null) return [{...item, message: newMessage.text}]

        return []
      })

  const defaultPreset = {
    name: isCreate ? '' : selectedPreset?.name ?? '',
    description: isCreate ? '' : selectedPreset?.description ?? '',
    private: isCreate ? true : selectedPreset?.private ?? true,
    includeChatHistory: false,
    conversationHistory: chatHistory,
    parameters: playgroundParameters,
    urlIdentifier: isCreate ? '' : selectedPreset?.urlIdentifier ?? '',
  }
  const [presetData, setPresetData] = useState(defaultPreset)

  const handleChange = (e: FormEvent<HTMLInputElement>) => {
    const {name, type, value, checked} = e.currentTarget

    // For the checkboxes, we want the value sent to the backend to be the opposite of "Enable sharing"
    setPresetData(prevState => ({
      ...prevState,
      [name]: type === 'checkbox' ? (name === 'private' ? !checked : checked) : value,
    }))
  }

  const nameInputRef = React.useRef<HTMLInputElement>(null)
  useEffect(() => {
    if (nameInputRef.current) {
      nameInputRef.current.focus()
    }

    if (errors && errors.url_identifier) {
      setNameError(`Name ${errors.url_identifier}`)
      nameInputRef.current?.focus()
    }

    if (errors && errors.name) {
      setNameError(`Name ${errors.name.join(', ')}`)
      nameInputRef.current?.focus()
    }

    if (errors && errors.conversation_history) {
      setConversationHistoryError(`Chat history ${errors.conversation_history}`)
    }
  }, [errors])

  const descriptionInputRef = React.useRef<HTMLInputElement>(null)

  const validateForm = async (event: React.FormEvent) => {
    event.preventDefault()

    const {name, description} = presetData
    const sizeMsg = (param: string, size: number) => `${param} cannot be longer than ${size} characters`

    setNameError(null)
    setDescriptionError(null)
    setConversationHistoryError(null)

    const noName = name.trim().length === 0
    const nameTooLong = name.length > NAME_MAX_SIZE
    const descTooLong = description && description.length > DESCRIPTION_MAX_SIZE

    if (noName) {
      setNameError('Name is required')
      nameInputRef.current?.focus()
    }
    if (nameTooLong) {
      setNameError(sizeMsg('Name', NAME_MAX_SIZE))
      nameInputRef.current?.focus()
    }
    if (descTooLong) {
      setDescriptionError(sizeMsg('Description', DESCRIPTION_MAX_SIZE))
      if (!noName && !nameTooLong) {
        descriptionInputRef.current?.focus()
      }
    }

    if (noName || nameTooLong || descTooLong) {
      return
    }

    onSubmit(presetData)
  }

  return (
    <Dialog
      title={<div {...testIdProps('save-preset-dialog')}>{dialogTitle}</div>}
      width="large"
      onClose={onClose}
      footerButtons={[
        {
          buttonType: 'default',
          content: 'Cancel',
          onClick: onClose,
          form: 'preset-dialog-form',
        },
        {
          buttonType: 'primary',
          content: isCreate ? 'Create preset' : 'Update preset',
          form: 'preset-dialog-form',
          type: 'submit',
        },
      ]}
    >
      <div className="d-inline-flex flex-justify-between width-full mb-3">
        <span>Presets save your current parameters, chat history, and state.</span>
      </div>

      {conversationHistoryError ? (
        <Banner
          hideTitle
          variant="critical"
          title="Chat history too large"
          description={conversationHistoryError}
          className="mb-3"
          {...testIdProps('chat-history-error-banner')}
        />
      ) : (
        errors?.error && (
          <Banner
            hideTitle
            variant="critical"
            title="Something went wrong"
            description={errors.error}
            className="mb-3"
            {...testIdProps('generic-error-banner')}
          />
        )
      )}

      <form onSubmit={validateForm} id="preset-dialog-form">
        <FormControl id="preset-name-input" required sx={{mb: 3}}>
          <FormControl.Label>Name</FormControl.Label>
          <TextInput
            name="name"
            onChange={handleChange}
            placeholder=""
            value={presetData.name}
            validationStatus={nameError ? 'error' : undefined}
            ref={nameInputRef}
            sx={{width: '100%'}}
          />
          {nameError ? <FormControl.Validation variant="error">{nameError}</FormControl.Validation> : null}
        </FormControl>

        <FormControl id="preset-description-input" sx={{mb: 3}}>
          <FormControl.Label>Description</FormControl.Label>
          <TextInput
            name="description"
            onChange={handleChange}
            placeholder=""
            value={presetData.description}
            validationStatus={descriptionError ? 'error' : undefined}
            ref={descriptionInputRef}
            sx={{width: '100%'}}
          />
          {descriptionError ? (
            <FormControl.Validation variant="error">{descriptionError}</FormControl.Validation>
          ) : null}
        </FormControl>

        <FormControl id="preset-include-chat-history-checkbox" sx={{mb: '16px'}}>
          <Checkbox name="includeChatHistory" checked={presetData.includeChatHistory} onChange={handleChange} />
          <FormControl.Label>Save chat history</FormControl.Label>
          <FormControl.Caption>
            Chat history in this preset will be saved and visible to others when shared.
            {shouldSaveImages ? null : ' Note: Image attachments are not saved with the preset.'}
          </FormControl.Caption>
        </FormControl>

        <FormControl id="preset-private-checkbox">
          <Checkbox name="private" checked={!presetData.private} onChange={handleChange} />
          <FormControl.Label>Enable sharing</FormControl.Label>
          <FormControl.Caption>
            Anyone with the URL will be able to view and use this preset, but not edit. Presets are private by default.
          </FormControl.Caption>
        </FormControl>
      </form>
    </Dialog>
  )
}

import {debounce} from '@github/mini-throttle'
import {sendEvent} from '@github-ui/hydro-analytics'
import {testIdProps} from '@github-ui/test-id-props'
import {ScopedCommands} from '@github-ui/ui-commands'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {Button, FormControl, Portal, Textarea} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {type RefObject, useCallback, useEffect, useRef, useState} from 'react'

import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import styles from './PersonalInstructionsDialog.module.css'
import {PersonalInstructionsTemplates} from './PersonalInstructionsTemplates'

const useElementHeight = (element: RefObject<HTMLElement>, wait: number = 500) => {
  const defaultHeight = 48
  const [height, setHeight] = useState<number>(defaultHeight)

  useEffect(() => {
    const handleResize = debounce(() => {
      if (element?.current) {
        setHeight(element.current.clientHeight ?? defaultHeight)
      }
    }, wait)
    const resizeObserver = new ResizeObserver(handleResize)

    if (element?.current) {
      resizeObserver.observe(element.current)
    }

    return () => {
      handleResize.cancel()
      resizeObserver?.disconnect?.()
    }
  }, [element, wait])

  return height
}

export interface DialogProps {
  onDismiss: () => void
}

export const PersonalInstructionsDialog = ({onDismiss}: DialogProps): JSX.Element => {
  const state = useChatState()
  const manager = useChatManager()
  const [prompt, setPrompt] = useState(state.personalInstructions ?? '')
  const [errorMessage, setErrorMessage] = useState<string | undefined>(undefined)
  const [isSaving, setIsSaving] = useState<boolean>(false)
  const maxCharLimit = 600
  const textAreaRef = useRef<HTMLTextAreaElement>(null)
  const actionListRef = useRef<HTMLDivElement>(null)
  const [lastSelectedTemplate, setLastSelectedTemplate] = useState<string>('')
  const templatesHeight = useElementHeight(actionListRef as RefObject<HTMLElement>)

  // Scroll to the bottom of the textarea when the prompt changes
  useLayoutEffect(() => {
    if (textAreaRef?.current) {
      textAreaRef.current.scrollTop = textAreaRef.current.scrollHeight
    }
  }, [prompt])

  const savePersonalInstructions = useCallback(async () => {
    // Prevents double saving
    if (isSaving) return
    setIsSaving(true)

    if (lastSelectedTemplate) {
      sendEvent('copilot_personal_instruction_template_usage', {
        content: lastSelectedTemplate,
      })
    }

    try {
      const resp = await verifiedFetchJSON('/copilot/personal_instructions', {
        method: 'POST',
        body: {
          prompt,
        },
      })
      if (resp.ok) {
        // Send event for successful save
        sendEvent('dotcom_chat.activate', {
          target: 'PERSONAL_INSTRUCTIONS_SAVE',
          mode: 'immersive',
        })
        // Updates the context with new personal instructions
        manager.dispatch({type: 'SET_PERSONAL_INSTRUCTIONS', personalInstructions: prompt})
        onDismiss()
      } else {
        const errorData = await resp.json()
        setErrorMessage(String(errorData.errorMessage))
      }
    } catch {
      setErrorMessage('An error occurred while saving your personal instructions.')
    } finally {
      setIsSaving(false)
    }
  }, [isSaving, prompt, manager, onDismiss, lastSelectedTemplate])

  const appendPrompt = (templateName: string, template: string | undefined) => {
    if (!template) return

    const newPrompt = prompt ? `${prompt}\n${template}` : template

    setPrompt(newPrompt)
    setLastSelectedTemplate(templateName)
    textAreaRef?.current?.focus()
  }

  const onSubmit = () => {
    void savePersonalInstructions()
  }

  const handleDismiss = useCallback(() => {
    // Send event for dismiss
    sendEvent('dotcom_chat.dismiss', {
      target: 'PERSONAL_INSTRUCTIONS_DISMISS',
      mode: 'immersive',
    })
    onDismiss()
  }, [onDismiss])

  return (
    <Portal>
      <Dialog
        onClose={handleDismiss}
        title="Personal instructions"
        subtitle="Set up Copilot to align with your workflows and preferences. These instructions will only impact your personal conversation."
        width="large"
        renderBody={() => (
          <Dialog.Body>
            <form onSubmit={savePersonalInstructions}>
              <FormControl>
                <FormControl.Label visuallyHidden>Instructions</FormControl.Label>
                <div className="width-full position-relative">
                  <ScopedCommands commands={{'github:submit-form': onSubmit}}>
                    <Textarea
                      ref={textAreaRef}
                      className="width-full"
                      style={{paddingBottom: `${templatesHeight}px`}}
                      aria-label="Prompt"
                      rows={7}
                      name="prompt"
                      placeholder="Your instructions"
                      value={prompt}
                      validationStatus={errorMessage || prompt.length > maxCharLimit ? 'error' : undefined}
                      {...testIdProps('prompt-input')}
                      onChange={e => {
                        setPrompt(e.target.value)
                        setErrorMessage(undefined)
                      }}
                    />
                    <PersonalInstructionsTemplates ref={actionListRef} onSelect={appendPrompt} />
                  </ScopedCommands>
                </div>
                <CharacterCount text={prompt} promptCharLimit={maxCharLimit} />
                {errorMessage && (
                  <FormControl.Validation variant="error">
                    <span {...testIdProps('error-message')}>{errorMessage}</span>
                  </FormControl.Validation>
                )}
              </FormControl>
            </form>
          </Dialog.Body>
        )}
        renderFooter={() => (
          <div className={styles.footerContainer}>
            <Button variant="default" onClick={handleDismiss}>
              Cancel
            </Button>
            <Button
              loading={isSaving}
              loadingAnnouncement="Saving personal instructions"
              variant="primary"
              onClick={savePersonalInstructions}
            >
              Save
            </Button>
          </div>
        )}
      />
    </Portal>
  )
}

function CharacterCount({text, promptCharLimit}: {text: string; promptCharLimit: number}) {
  const currentCount = (
    <>
      <span className="text-tabular-nums" {...testIdProps('current-character-count')}>
        {text.length}
      </span>{' '}
      / {promptCharLimit} characters
    </>
  )
  return (
    <>
      {text.length > promptCharLimit ? (
        <FormControl.Validation variant="error">{currentCount}</FormControl.Validation>
      ) : (
        // This is a direct child, it just doesn't know that because it is a fragment within a function call
        // eslint-disable-next-line primer-react/direct-slot-children
        <FormControl.Caption>{currentCount}</FormControl.Caption>
      )}
    </>
  )
}

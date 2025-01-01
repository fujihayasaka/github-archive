import {ScopedCommands} from '@github-ui/ui-commands'
import {PaperAirplaneIcon} from '@primer/octicons-react'
import {TextInput} from '@primer/react'
import {type FormEvent, useEffect, useState} from 'react'

import type {UseWorkbenchReturn} from '../hooks/use-workbench'
import type {ElementPayload} from '../targeted-edits/types'
import {useTargetedEdits} from '../targeted-edits/use-targeted-edits'
import {SPARK_PREVIEW_CONTAINER_ID} from './PreviewArea/PreviewArea'
import styles from './TargetedEditsInput.module.css'

interface TargetedEditsInputProps {
  element: ElementPayload
  submitPrompt: UseWorkbenchReturn['submitPrompt']
}

export function TargetedEditsInput({element, submitPrompt}: TargetedEditsInputProps) {
  const {disableTargetedEdits} = useTargetedEdits()
  const [previewAreaBounds, setPreviewAreaBounds] = useState<{
    top: number
    left: number
    width: number
    height: number
  }>({
    top: 0,
    left: 0,
    width: 0,
    height: 0,
  })

  const [prompt, setPrompt] = useState<string>('')

  useEffect(() => {
    const sparkPreviewContainer = document.getElementById(SPARK_PREVIEW_CONTAINER_ID)! as HTMLDivElement
    const updatePosition = () => {
      const {top, left, width, height} = sparkPreviewContainer.getBoundingClientRect()
      setPreviewAreaBounds({top, left, width, height})
    }

    updatePosition()

    const resizeObserver = new ResizeObserver(() => {
      updatePosition()
    })
    resizeObserver.observe(sparkPreviewContainer)

    return () => {
      resizeObserver.unobserve(sparkPreviewContainer)
      resizeObserver.disconnect()
    }
  }, [])

  const {position} = element

  const handleSubmit = async (e?: FormEvent) => {
    e?.preventDefault()

    if (prompt.trim().length === 0) return

    const location = element.location ?? element.component.location!

    submitPrompt(prompt, 'refine', 'targeted_prompt', false, {
      locations: [
        {
          filePath: location.start.filePath,
          startLine: location.start.line,
          startColumn: location.start.column,
          endLine: location.end.line,
          endColumn: location.end.column,
        },
      ],
    })
    disableTargetedEdits()
  }

  return (
    <div
      className={styles.container}
      style={{
        position: 'fixed',
        zIndex: 10,
        top: previewAreaBounds.top + position.top + position.height + 8,
        left: previewAreaBounds.left + position.left + position.width / 2,
        transform: 'translateX(-50%)', // This centers the element horizontally
      }}
    >
      <ScopedCommands commands={{'github:submit-form': () => handleSubmit()}}>
        <form className={styles.form} onSubmit={handleSubmit}>
          <TextInput
            block
            trailingAction={<TextInput.Action type="submit" icon={PaperAirplaneIcon} aria-label="Send now" />}
            placeholder="Make a quick change here..."
            value={prompt}
            onChange={e => setPrompt(e.target.value)}
          />
        </form>
      </ScopedCommands>
    </div>
  )
}

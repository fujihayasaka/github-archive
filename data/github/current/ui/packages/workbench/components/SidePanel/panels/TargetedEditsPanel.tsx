import {FormControl, Label, Textarea, TextInput} from '@primer/react'
import {useEffect, useRef, useState} from 'react'

import {useTargetedEditsContext} from '../../../contexts/TargetedEditsContext'
import type {ElementPayload} from '../../../targeted-edits/types'
import {ColorPickerItem} from '../ColorPickerItem'
import {Section} from '../Section'
import styles from './TargetedEditsPanel.module.css'

interface TargetedEditsPanelProps {
  element: ElementPayload
  onClose: () => void
}

export function TargetedEditsPanel({element}: TargetedEditsPanelProps) {
  const {modifyJsxClassName, modifyJsxText} = useTargetedEditsContext()

  const [localText, setLocalText] = useState<string>(element.text ?? '')
  const [localClassName, setLocalClassName] = useState<string>((element.props.className as string) ?? '')

  const isEditingClassName = useRef(false)

  const location = element.location ?? element.component.location!

  const handleClassNameChange = (event: React.ChangeEvent<HTMLTextAreaElement>) => {
    const newClassName = event.target.value
    setLocalClassName(newClassName)
    modifyJsxClassName({
      filePath: location.start.filePath,
      line: location.start.line,
      column: location.start.column,
      className: newClassName,
      replace: true,
    })
  }

  const handleTextChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    setLocalText(event.target.value)
  }

  useEffect(() => {
    if (element.text) {
      setLocalText(element.text)
    }
  }, [element.text])

  /**
   * This can happen when the user updated the color / background color, which changes the className of the element
   */
  useEffect(() => {
    if (element.props.className && element.props.className !== localClassName && !isEditingClassName.current) {
      setLocalClassName(element.props.className as string)
    }
  }, [element.props.className, localClassName])

  return (
    <>
      <div className={styles.headerContainer}>
        <div className="d-flex flex-justify-between">
          <Label>{element.tag}</Label>
        </div>
      </div>
      {element.text && (
        <Section title="Content">
          <FormControl>
            <FormControl.Label visuallyHidden>Content</FormControl.Label>
            <TextInput
              block
              name="name"
              value={localText}
              placeholder="Enter name"
              disabled={element.editable === false}
              onChange={handleTextChange}
              onBlur={() => {
                modifyJsxText({
                  filePath: location.start.filePath,
                  line: location.start.line,
                  column: location.start.column,
                  content: localText,
                })
              }}
            />
            {element.editable === false && (
              <FormControl.Caption>
                This content is dynamically generated and cannot be edited directly. To make changes, please make a new
                iteration.
              </FormControl.Caption>
            )}
          </FormControl>
        </Section>
      )}
      <Section title="Appearance">
        <Section.Group label="Text" columns={1}>
          <ColorPickerItem
            token="foreground"
            label="Color"
            activeColor={localClassName?.split(' ').find(c => c.startsWith('text-')) ?? ''}
            onChange={color => {
              modifyJsxClassName({
                filePath: location.start.filePath,
                line: location.start.line,
                column: location.start.column,
                className: color,
                replace: false,
              })
            }}
          />
        </Section.Group>
        <Section.Group label="Background" columns={1}>
          <ColorPickerItem
            token="background"
            label="Color"
            activeColor={localClassName.split(' ').find(c => c.startsWith('bg-')) ?? ''}
            onChange={color => {
              modifyJsxClassName({
                filePath: location.start.filePath,
                line: location.start.line,
                column: location.start.column,
                className: color,
                replace: false,
              })
            }}
          />
        </Section.Group>
        <Section.Group label="Border" columns={1}>
          <ColorPickerItem
            token="background"
            label="Color"
            activeColor={localClassName.split(' ').find(c => c.startsWith('bg-')) ?? ''}
            onChange={color => {
              modifyJsxClassName({
                filePath: location.start.filePath,
                line: location.start.line,
                column: location.start.column,
                className: color,
                replace: false,
              })
            }}
          />
        </Section.Group>
      </Section>

      <Section title="Advanced">
        <FormControl>
          <FormControl.Label visuallyHidden>Class</FormControl.Label>
          <Textarea
            block
            rows={3}
            value={localClassName}
            onChange={handleClassNameChange}
            resize="vertical"
            onFocus={() => (isEditingClassName.current = true)}
            onBlur={() => (isEditingClassName.current = false)}
            placeholder="Enter className"
          />
        </FormControl>
      </Section>
    </>
  )
}

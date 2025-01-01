import {LABELS} from './constants/labels'
import {Dialog, FormControl, Textarea, TextInput} from '@primer/react'
import styles from './RepositoryLabel.module.css'
import {useEffect, useRef, useState} from 'react'
import {AriaAlert, Banner} from '@primer/react/experimental'
import {isValidColor, LabelColorPicker, randomHexColor} from './components/LabelColorPicker'
import {LabelPreview} from './LabelPreview'
import {CommandButton, ScopedCommands} from '@github-ui/ui-commands'

export type DialogFormProps = {
  onDialogClose: () => void
  onDialogSubmit: (
    data: {name: string; description: string; color: string},
    isSubmitting: (isSubmitting: boolean) => void,
  ) => void
  submissionErrors?: string
  submitButtonText?: string
  formTitle: string
  namePlaceholder?: string
  descriptionPlaceholder?: string
  initialValues?: {
    name: string
    description?: string | null
    color: string
  }
}

export function DialogForm({
  onDialogClose,
  onDialogSubmit,
  formTitle = LABELS.newLabel,
  submissionErrors = '',
  submitButtonText = LABELS.createButtonText,
  namePlaceholder,
  descriptionPlaceholder,
  initialValues,
}: DialogFormProps) {
  const [name, setName] = useState(initialValues?.name ?? '')
  const [description, setDescription] = useState(initialValues?.description ?? '')
  const [color, setColor] = useState(() => {
    return initialValues?.color ? `#${initialValues.color}` : randomHexColor()
  })
  const [colorInputValue, setColorInputValue] = useState(color)

  const [isSubmitting, setIsSubmitting] = useState(false)

  const [nameValidationError, setNameValidationError] = useState<string | null>(null)
  const [colorValidationError, setColorValidationError] = useState<string | null>(null)

  const errorBanner = useRef<HTMLDivElement>(null)
  const nameInputRef = useRef<HTMLInputElement>(null)
  const colorInputRef = useRef<HTMLInputElement>(null)

  const handleSubmit = () => {
    if (isSubmitting) {
      return
    }

    setIsSubmitting(true)
    setNameValidationError(null)
    setColorValidationError(null)

    if (!name) {
      setNameValidationError(LABELS.nameRequired)
      setIsSubmitting(false)
      nameInputRef.current?.focus()
      return
    }

    if (!isValidColor(colorInputValue)) {
      setColorValidationError(LABELS.invalidColor)
      setIsSubmitting(false)
      colorInputRef.current?.focus()
      return
    }

    const input = {
      name: name.trim(),
      description: description.trim(),
      color: color.replace('#', ''),
    }

    onDialogSubmit(input, setIsSubmitting)
    return
  }

  const handleColorPickerChange = (newColor: string) => {
    setColorInputValue(newColor)
    if (isValidColor(newColor)) {
      setColor(newColor)
      setColorValidationError(null)
    }
  }

  useEffect(() => {
    if (submissionErrors && submissionErrors.length > 0 && errorBanner?.current) {
      errorBanner.current.focus()
    }
  }, [errorBanner, submissionErrors])

  return (
    <ScopedCommands
      commands={{
        'repository-label:save-label-submit': handleSubmit,
        'repository-label:cancel-save-label': onDialogClose,
      }}
    >
      <Dialog title={formTitle} onClose={onDialogClose} className={styles.dialogForm}>
        <Dialog.Body className={styles.dialogFormBody}>
          {submissionErrors?.length > 0 ? (
            <Banner
              ref={errorBanner}
              title="Error"
              description={<AriaAlert>{submissionErrors}</AriaAlert>}
              variant="critical"
              role="alert"
            />
          ) : null}
          <div className={styles.dialogFormPreviewContainer}>
            <LabelPreview name={name ? name : LABELS.labelPreview} color={color?.replace('#', '')} />
          </div>
          <FormControl className={styles.dialogFormInput} id="label-form-name">
            <FormControl.Label htmlFor="label-form-name">{LABELS.name}</FormControl.Label>
            <TextInput
              value={name}
              onChange={e => setName(e.target.value)}
              className={styles.dialogFormInput}
              ref={nameInputRef}
              maxLength={50}
              placeholder={namePlaceholder}
            />
            {nameValidationError && (
              <FormControl.Validation variant="error">{nameValidationError}</FormControl.Validation>
            )}
          </FormControl>
          <FormControl className={styles.dialogFormInput} id="label-form-description">
            <FormControl.Label htmlFor="label-form-description">{LABELS.description}</FormControl.Label>
            <Textarea
              value={description}
              onChange={e => setDescription(e.target.value)}
              rows={3}
              className={styles.dialogFormInput}
              placeholder={descriptionPlaceholder}
            />
          </FormControl>
          <FormControl className={styles.dialogFormInput} id="label-form-color">
            <LabelColorPicker color={color} onChangeCallback={handleColorPickerChange} ref={colorInputRef} />
            <FormControl.Label visuallyHidden>{LABELS.color}</FormControl.Label>
            {colorValidationError && (
              <FormControl.Validation variant="error">{colorValidationError}</FormControl.Validation>
            )}
          </FormControl>
        </Dialog.Body>
        <Dialog.Footer className={styles.dialogFormButtonGroup}>
          <CommandButton commandId="repository-label:cancel-save-label" disabled={isSubmitting}>
            {LABELS.cancelButtonText}
          </CommandButton>
          <CommandButton
            commandId="repository-label:save-label-submit"
            variant="primary"
            loading={isSubmitting}
            showKeybindingHint
          >
            {submitButtonText}
          </CommandButton>
        </Dialog.Footer>
      </Dialog>
    </ScopedCommands>
  )
}

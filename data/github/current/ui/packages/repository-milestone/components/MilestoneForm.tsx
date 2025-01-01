import {useCallback, useRef, useState, type Dispatch, type ReactNode, type SetStateAction} from 'react'
import {DatePicker} from '@github-ui/date-picker'
import {graphql, useFragment} from 'react-relay'
import {Button, FormControl, Heading, Textarea, TextInput} from '@primer/react'

import styles from './MilestoneForm.module.css'
import {LABELS} from '../constants/labels'
import type {UserSettingsOptionConfig} from '@github-ui/issue-create/getSafeConfig'
import type {CreateMilestoneInput} from '../mutations/__generated__/createRepositoryMilestoneMutation.graphql'
import type {MilestoneFormRepositoryQueryInternal$key} from './__generated__/MilestoneFormRepositoryQueryInternal.graphql'
import {Banner} from '@primer/react/experimental'

export type MilestoneInitialValues = {
  id?: string
  title?: string
  description?: string | null
  dueOn?: string | null
}

export type MilestoneFormProps = {
  repository: MilestoneFormRepositoryQueryInternal$key
  optionConfig?: UserSettingsOptionConfig
  onCancel?: () => void
  formTitle?: string
  formDescription?: ReactNode
  formSubmitLabel?: string
  submissionErrors?: string | null
  initialValues?: MilestoneInitialValues
  onSubmit: (input: CreateMilestoneInput, setIsSubmitting: Dispatch<SetStateAction<boolean>>) => void
  onToggleMilestoneState?: (
    e: React.MouseEvent<HTMLButtonElement>,
    setIsSubmitting: Dispatch<SetStateAction<boolean>>,
  ) => void
  toggleStateLabel?: string
}

export function MilestoneForm({
  repository,
  onCancel,
  formTitle,
  formDescription,
  formSubmitLabel = LABELS.createMilestone,
  onSubmit,
  submissionErrors,
  initialValues,
  onToggleMilestoneState,
  toggleStateLabel,
}: MilestoneFormProps) {
  const [title, setTitle] = useState(initialValues?.title || '')
  const [description, setDescription] = useState(initialValues?.description || '')
  const [dueDate, setDueDate] = useState<Date | null>(() => {
    if (initialValues?.dueOn) {
      return new Date(initialValues.dueOn)
    }
    return null
  })
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [titleValidationError, setTitleValidationError] = useState<string | null>(null)

  const titleInputRef = useRef<HTMLInputElement>(null)

  const repositoryData = useFragment(
    graphql`
      fragment MilestoneFormRepositoryQueryInternal on Repository {
        id
      }
    `,
    repository,
  )

  const handleSubmit = useCallback(
    async (e: React.FormEvent) => {
      if (isSubmitting) {
        return
      }

      e.preventDefault()

      setIsSubmitting(true)
      setTitleValidationError(null)

      if (!title.trim()) {
        setTitleValidationError(LABELS.titleRequired)
        titleInputRef.current?.focus()
        setIsSubmitting(false)
        return
      }

      let normalizedDueOn: string | null = null
      if (dueDate) {
        const selectedYear = dueDate.getFullYear()
        const selectedMonth = dueDate.getMonth()
        const selectedDay = dueDate.getDate()

        const utcDate = new Date(Date.UTC(selectedYear, selectedMonth, selectedDay))

        normalizedDueOn = utcDate.toISOString()
      }

      const input: CreateMilestoneInput = {
        repositoryId: repositoryData.id,
        title: title.trim(),
        description: description?.trim(),
        dueOn: normalizedDueOn,
      }

      onSubmit(input, setIsSubmitting)
      return
    },
    [description, dueDate, onSubmit, repositoryData, title, isSubmitting],
  )

  const onDatePickerChange = (date: Date | null) => {
    setDueDate(date)
  }

  const handleTitleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setTitle(e.target.value)
    if (titleValidationError) {
      setTitleValidationError(null)
    }
  }

  return (
    <div className={styles.formContainer} id="milestone-create-form" data-hpc>
      {submissionErrors && (
        <Banner
          aria-label="Error"
          title="Error"
          description={submissionErrors}
          variant="critical"
          className={styles.errorBanner}
        />
      )}
      <div>
        {formTitle && (
          <Heading as="h1" variant="medium" className={styles.milestonePageTitle}>
            {formTitle}
          </Heading>
        )}
        {formDescription}
      </div>

      <form onSubmit={handleSubmit}>
        <div className={styles.formWrapper}>
          <FormControl className={styles.formControl} id="milestone-title" disabled={isSubmitting}>
            <FormControl.Label htmlFor="milestone-title">{LABELS.title}</FormControl.Label>
            <TextInput
              block
              value={title}
              onChange={handleTitleChange}
              placeholder={LABELS.titlePlaceholder}
              ref={titleInputRef}
            />
            {titleValidationError && (
              <FormControl.Validation variant="error">{titleValidationError}</FormControl.Validation>
            )}
          </FormControl>

          <FormControl className={styles.formControl} id="milestone-due-on">
            <FormControl.Label htmlFor="milestone-due-on">{LABELS.dueDate}</FormControl.Label>
            <DatePicker
              variant="single"
              showClearButton
              value={dueDate}
              onChange={onDatePickerChange}
              disabled={isSubmitting}
              dateFormat="MMM d, yyyy"
              placeholder={LABELS.datePlaceholder}
              anchorClassName={styles.datePickerAnchor}
            />
          </FormControl>

          <FormControl className={styles.formControl} id="milestone-description" disabled={isSubmitting}>
            <FormControl.Label htmlFor="milestone-description">{LABELS.description}</FormControl.Label>
            <Textarea
              value={description}
              onChange={e => setDescription(e.target.value)}
              rows={5}
              placeholder={LABELS.descriptionPlaceholder}
              block
            />
          </FormControl>
        </div>
        <div className={`${styles.buttonRow} ${onToggleMilestoneState ? 'flex-justify-between' : 'flex-justify-end'}`}>
          {onToggleMilestoneState && toggleStateLabel && (
            <Button onClick={e => onToggleMilestoneState?.(e, setIsSubmitting)}>{toggleStateLabel}</Button>
          )}
          <div className={styles.buttonGroup}>
            <Button onClick={onCancel}>{LABELS.cancel}</Button>
            <Button type="submit" variant="primary" loading={isSubmitting}>
              {formSubmitLabel}
            </Button>
          </div>
        </div>
      </form>
    </div>
  )
}

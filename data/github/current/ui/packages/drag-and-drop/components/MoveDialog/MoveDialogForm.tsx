import {DatePicker, type SingleDatePickerProps} from '@github-ui/date-picker'
import {TriangleDownIcon} from '@primer/octicons-react'
import {
  Button,
  FormControl,
  Select,
  SelectPanel,
  type SelectPanelProps,
  type SelectProps,
  TextInput,
  type TextInputProps,
} from '@primer/react'
import {clsx} from 'clsx'
import React from 'react'
import {
  type ChangeEvent,
  createContext,
  type ReactElement,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from 'react'

import styles from './MoveDialogForm.module.css'

export const MoveDialogContext = createContext<{
  formLabel: string
  onChange: (helperText: string, isInValid: boolean) => void
  helperTextId?: string
}>({formLabel: '', onChange: () => {}})

export type Action = {
  /**
   * The value and label of the action
   */
  value: string
  /**
   * The input that is rendered when the action is selected
   */
  renderInput: ReactElement // TODO figure out how to limit types
}

export interface FormProps {
  /**
   * The movements that a user can take based on the type of action
   * For example, if the type of action is "reorder" then a action might be
   * "move item first"
   */
  actions: Action[]
  /**
   * Optional: Callback to set the validity of the form
   */
  onActionChange?: (e: ChangeEvent<HTMLSelectElement>) => void
  /**
   * Optional: The label of the action select
   */
  actionsLabel?: string
}

interface MoveDialogFormProps {
  /**
   * Callback to set the validity of the form
   */
  setIsInvalidOption: (isInvalid: boolean) => void
  /**
   * Callback to set the helper text of the form
   */
  setHelperText: (helperText: string) => void
  /**
   * The form option props
   */
  formProps: FormProps
  /***
   * The id of the helper text. Used to associate the helper text with the form input.
   */
  helperTextId: string
}

/**
 * A form that allows the user to move an item to a new position in the list.
 *
 * @param props InputProps
 */
export function MoveDialogForm(props: MoveDialogFormProps) {
  const {formProps, setIsInvalidOption, setHelperText, helperTextId} = props
  const {actions, onActionChange, actionsLabel} = formProps
  const [selectedAction, setSelectedAction] = useState(actions[0]?.value)

  const onChange = useCallback(
    (event: React.ChangeEvent<HTMLSelectElement>) => {
      onActionChange?.(event)
      const action = actions.find(a => a.value === event.target.value)
      if (action) {
        setSelectedAction(action.value)
      }
    },
    [actions, onActionChange],
  )

  return (
    <MoveDialogContext.Provider
      value={useMemo(
        () => ({
          formLabel: selectedAction ?? '',
          onChange: (helperText, isInValid) => {
            setHelperText(helperText)
            setIsInvalidOption(isInValid)
          },
          helperTextId,
        }),
        [selectedAction, setHelperText, helperTextId, setIsInvalidOption],
      )}
    >
      <div className={clsx(styles.form)}>
        {actions.length > 1 && (
          <FormControl required>
            <FormControl.Label>{actionsLabel ?? 'Action'}</FormControl.Label>
            <Select block onChange={onChange}>
              {actions.map(action => (
                <Select.Option key={action.value} value={action.value}>
                  {action.value}
                </Select.Option>
              ))}
            </Select>
          </FormControl>
        )}
        {actions.find(a => a.value === selectedAction)?.renderInput}
      </div>
    </MoveDialogContext.Provider>
  )
}

type OptionProps = {
  helperText: string
  isInvalid?: boolean
}

// add ref to props to support `React.forwardRef`

export const SingleSelect = React.forwardRef<HTMLSelectElement, OptionProps & SelectProps>((props, ref) => {
  const {helperText, isInvalid, ...rest} = props
  const {formLabel, onChange: parentOnChange, helperTextId} = useContext(MoveDialogContext)

  useEffect(() => {
    parentOnChange(helperText ?? '', !!isInvalid)
  }, [helperText, isInvalid, parentOnChange])

  return (
    <FormControl required>
      <FormControl.Label>{formLabel}</FormControl.Label>
      <Select
        block
        aria-invalid={isInvalid}
        validationStatus={isInvalid ? 'error' : undefined}
        aria-describedby={helperTextId}
        ref={ref}
        {...rest}
      />
    </FormControl>
  )
})

SingleSelect.displayName = 'MoveDialogForm.SingleSelect'

// we only want to show form validation after `onSubmit` is called
export const Text = React.forwardRef<HTMLInputElement, OptionProps & TextInputProps>((props, ref) => {
  const {isInvalid, helperText, ...rest} = props
  const {formLabel, onChange: parentOnChange, helperTextId} = useContext(MoveDialogContext)

  useEffect(() => {
    parentOnChange(helperText, !!isInvalid)
  }, [helperText, isInvalid, parentOnChange])

  return (
    <FormControl required>
      <FormControl.Label>{formLabel}</FormControl.Label>
      <TextInput
        block
        aria-invalid={isInvalid}
        validationStatus={isInvalid ? 'error' : undefined}
        aria-describedby={helperTextId}
        ref={ref}
        {...rest}
      />
    </FormControl>
  )
})

Text.displayName = 'MoveDialogForm.Text'

export function MultiSelect(props: SelectPanelProps & OptionProps) {
  const {isInvalid, helperText, ...rest} = props
  const {formLabel, onChange: parentOnChange} = useContext(MoveDialogContext) // TODO: helperTextId

  useEffect(() => {
    parentOnChange(helperText, !!isInvalid)
  }, [helperText, isInvalid, parentOnChange])

  const renderAnchor = (buttonProps: React.HTMLAttributes<HTMLElement>) => {
    const {children, ...otherProps} = buttonProps
    return (
      <Button trailingAction={TriangleDownIcon} block {...otherProps}>
        {children}
      </Button>
    )
  }

  const selectPanelProps = {
    ...rest,
    renderAnchor,
  }

  // TODO: Figure out how to handle the aria-describedby
  return (
    <FormControl required>
      <FormControl.Label>{formLabel}</FormControl.Label>
      <SelectPanel {...selectPanelProps} />
    </FormControl>
  )
}

export function DateInput(props: SingleDatePickerProps & OptionProps) {
  const {isInvalid, helperText, ...datePickerProps} = props
  const {formLabel, onChange: parentOnChange, helperTextId} = useContext(MoveDialogContext)

  const defaultDatePickerProps: Partial<SingleDatePickerProps> = {
    anchor: 'button',
    anchorClassName: styles.datePickerAnchor,
    compressedHeader: false,
    confirmation: false,
    confirmUnsavedClose: true,
    dateFormat: 'long',
    placeholder: formLabel,
    showTodayButton: true,
    showClearButton: false,
    variant: 'single',
    weekStartsOn: 'Sunday',
  }

  useEffect(() => {
    parentOnChange(helperText, !!isInvalid)
  }, [helperText, isInvalid, parentOnChange])

  const merged = {...defaultDatePickerProps, ...datePickerProps}

  return (
    <FormControl required>
      <FormControl.Label>{formLabel}</FormControl.Label>
      <DatePicker {...merged} aria-describedby={helperTextId} />
    </FormControl>
  )
}

MoveDialogForm.SingleSelect = SingleSelect
MoveDialogForm.Text = Text
MoveDialogForm.MultiSelect = MultiSelect
MoveDialogForm.Date = DateInput
// Convenience alias
MoveDialogForm.SingleSelectOption = Select.Option

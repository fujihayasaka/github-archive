import {isEmptyPropertyValue} from '@github-ui/custom-properties-types/helpers'
import {ownerPath} from '@github-ui/paths'
import {useDebounce} from '@github-ui/use-debounce'
import {TriangleDownIcon, XCircleFillIcon, XIcon} from '@primer/octicons-react'
import {AnchoredOverlay, Button, Checkbox, FormControl, IconButton, Link, TextInput, Truncate} from '@primer/react'
import {clsx} from 'clsx'
import {useRef, useState} from 'react'

import {mixedValuePlaceholder} from '../CustomPropertySelectPanel'
import {validateValue} from '../validate'
import styles from './CustomPropertyStringEditor.module.css'
import {WarningMessage} from './WarningMessage'

interface Props {
  propertyValue: string
  defaultValue?: string | null
  regexPattern?: string | null
  mixed?: boolean
  orgName: string
  onChange: (value: string) => void
}

export function CustomPropertyStringEditor(props: Props) {
  const {mixed, propertyValue, defaultValue, onChange} = props
  const [open, setOpen] = useState(false)
  const closeButtonRef = useRef<HTMLButtonElement>(null)

  const anchorLabel = getDisplayAnchorLabel(propertyValue, defaultValue, mixed)

  return (
    <AnchoredOverlay
      focusTrapSettings={{initialFocusRef: closeButtonRef}}
      open={open}
      onOpen={() => setOpen(true)}
      onClose={() => setOpen(false)}
      side="outside-bottom"
      overlayProps={{role: 'dialog', sx: {width: 320}, title: 'Set a text value'}}
      renderAnchor={anchorProps => (
        <Button
          {...anchorProps}
          block
          className={styles.anchorButton}
          alignContent="start"
          trailingAction={TriangleDownIcon}
        >
          <Truncate maxWidth="100%" title={anchorLabel}>
            {anchorLabel}
          </Truncate>
        </Button>
      )}
    >
      <div>
        <div
          className={clsx(
            mixed ? 'border-bottom-0' : 'border-bottom',
            'p-2 pl-3 d-flex flex-justify-between flex-items-center gap-2',
          )}
        >
          <div className={clsx(styles.overlayHeaderTitle, 'text-bold')}>Set a text value</div>
          <IconButton
            ref={closeButtonRef}
            aria-label="Close"
            variant="invisible"
            icon={XIcon}
            onClick={() => setOpen(false)}
          />
        </div>

        {mixed && <WarningMessage>Property has mixed values</WarningMessage>}

        {/* Ensure unmounting of the control to perform state reset. */}
        {open && (
          <InnerStringEditor
            {...props}
            onCancel={() => setOpen(false)}
            onChange={value => {
              onChange(value)
              setOpen(false)
            }}
          />
        )}
      </div>
    </AnchoredOverlay>
  )
}

interface InnerStringEditorProps extends Props {
  onCancel: () => void
}

function InnerStringEditor({
  propertyValue,
  defaultValue,
  regexPattern,
  orgName,
  mixed,
  onCancel,
  onChange,
}: InnerStringEditorProps) {
  const inputRef = useRef<HTMLInputElement>(null)
  const required = !!defaultValue

  const [defaultUsed, setDefaultUsed] = useState(!!defaultValue && !propertyValue && !mixed)
  const [value, setValue] = useState<string>(() => getInitialValue(propertyValue, defaultValue, mixed))
  const [error, setError] = useState<string | undefined>()

  const validateAndSetError = async (v: string) => {
    const validationError = await validate(v, required, regexPattern)
    setError(validationError)

    return validationError
  }

  const debouncedSetError = useDebounce(validateAndSetError, 300, {onChangeBehavior: 'cancel'})

  const setPropertyValue = async (v: string) => {
    setDefaultUsed(false)
    setValue(v)
    debouncedSetError(v)
  }

  const onApply = async () => {
    const validationError = await validateAndSetError(value)
    if (validationError) {
      return inputRef.current?.focus()
    }

    onChange(defaultUsed ? '' : value)
  }

  return (
    <div>
      <div className="p-3">
        <FormControl>
          <FormControl.Label visuallyHidden>Edit value</FormControl.Label>
          <TextInput
            block
            ref={inputRef}
            value={value}
            placeholder="Enter a value"
            onChange={e => setPropertyValue(e.target.value)}
            trailingAction={
              value ? (
                <TextInput.Action
                  onClick={() => setPropertyValue('')}
                  icon={XCircleFillIcon}
                  aria-label="Clear input"
                />
              ) : (
                <></>
              )
            }
          />

          {error && <FormControl.Validation variant="error">{error}</FormControl.Validation>}
        </FormControl>

        {defaultValue && (
          <FormControl className="mt-2">
            <Checkbox
              checked={defaultUsed}
              onChange={e => {
                if (e.target.checked) {
                  setDefaultUsed(true)
                  setValue(defaultValue)
                } else {
                  setPropertyValue('')
                }
              }}
            />
            <FormControl.Label>Use default value ({defaultValue})</FormControl.Label>
            <FormControl.Caption>
              Inherited from{' '}
              <Link inline href={ownerPath({owner: orgName})}>
                {orgName}
              </Link>
            </FormControl.Caption>
          </FormControl>
        )}
      </div>

      <div className="p-3 d-flex flex-justify-end gap-2 border-top">
        <Button onClick={onCancel}>Cancel</Button>
        <Button variant="primary" onClick={onApply}>
          Apply
        </Button>
      </div>
    </div>
  )
}

function getInitialValue(value: string, defaultValue?: string | null, mixed?: boolean) {
  if (mixed) {
    return ''
  }

  return value || defaultValue || ''
}

function validate(value: string, required: boolean, regexPattern?: string | null) {
  if (!value && required) {
    return 'This property is required and can’t be blank'
  }

  return validateValue(value, regexPattern || undefined)
}

function getDisplayAnchorLabel(value: string, defaultValue?: string | null, mixed?: boolean): string {
  if (mixed) {
    return mixedValuePlaceholder
  }

  if (!isEmptyPropertyValue(value)) {
    return value
  } else if (!isEmptyPropertyValue(defaultValue)) {
    return `default (${defaultValue})`
  } else {
    return 'Set value'
  }
}

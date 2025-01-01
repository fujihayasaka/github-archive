import {
  CustomPropertyBooleanSelectPanel,
  CustomPropertyMultiSelectPanel,
  CustomPropertySingleSelectPanel,
  OldCustomPropertyMultiSelectPanel,
  OldCustomPropertySingleSelectPanel,
} from '@github-ui/custom-properties-editing'
import type {PropertyDefinition, ValueType} from '@github-ui/custom-properties-types'
import type {OnDropArgs} from '@github-ui/drag-and-drop'
import {DragAndDrop, useDragAndDrop} from '@github-ui/drag-and-drop'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {RegexTesterDialog} from '@github-ui/regex-tester-dialog'
import {RegexPatternInput} from '@github-ui/regex-tester-dialog/RegexPatternInput'
import type {SafeHTMLString} from '@github-ui/safe-html'
import sudo from '@github-ui/sudo'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {GrabberIcon, KebabHorizontalIcon} from '@primer/octicons-react'
import {
  ActionList,
  ActionMenu,
  Button,
  Checkbox,
  FormControl,
  IconButton,
  Label,
  Link,
  Textarea,
  TextInput,
} from '@primer/react'
import {useEffect, useRef, useState} from 'react'

import {useSetBanner} from '../contexts/BannerContext'
import {definitionTypeLabels} from '../helpers/definition-type-labels'
import {useSavePropertyPath} from '../hooks/use-properties-paths'
import {type FormErrors, usePropertyDefinitionForm} from '../hooks/use-property-definition-form'
import {OrgConflictsDialog} from './OrgConflictsDialog'
import styles from './PropertyDefinitionSettings.module.css'

interface Props {
  definition?: PropertyDefinition
  existingPropertyNames: string[]
  setFormError: (error: SafeHTMLString) => void
  onCancel: () => void
  onSuccess: (propertyName: string) => void
}

export function PropertyDefinitionSettings({
  definition,
  existingPropertyNames,
  onSuccess,
  onCancel,
  setFormError,
}: Props) {
  const setBanner = useSetBanner()

  const [saving, setSaving] = useState(false)
  const [showRegexTestValueDialog, setShowRegexTestValueDialog] = useState(false)
  const isEditing = !!definition

  const {
    valueTypeField,
    propertyNameField,
    defaultValueField,
    allowedValuesField,
    newAllowedValueField,
    repoActorsEditingAllowedField,
    descriptionField,
    requiredField,
    regexField,
    regexEnabledField,
    validateForm,
  } = usePropertyDefinitionForm({definition, existingPropertyNames})
  const [typeDropdownOpen, setTypeDropdownOpen] = useState(false)
  const [showOrgConflicts, setShowOrgConflicts] = useState(false)

  const propertyNameRef = useRef<HTMLInputElement>(null)
  const regexInputRef = useRef<HTMLInputElement>(null)

  const propertyDescriptionRef = useRef<HTMLTextAreaElement>(null)
  const propertyStringDefaultValueRef = useRef<HTMLInputElement>(null)
  const propertySingleSelectDefaultValueRef = useRef<HTMLElement>(null)
  const propertyBooleanDefaultValueRef = useRef<HTMLButtonElement>(null)
  const propertyMultiSelectDefaultValueRef = useRef<HTMLElement>(null)
  const newAllowedValueRef = useRef<HTMLInputElement>(null)
  const allowedValuesItemsRefs = useRef<Array<React.RefObject<HTMLElement>>>([])

  const testRegexValuesRef = useRef<HTMLButtonElement>(null)

  const isText = valueTypeField.value === 'string'
  const isSingleSelect = valueTypeField.value === 'single_select'
  const isTrueFalse = valueTypeField.value === 'true_false'
  const isMultiSelect = valueTypeField.value === 'multi_select'

  const regexEnabled = isText && regexEnabledField.value

  const editingRedesignEnabled = useFeatureFlag('custom_properties_editing_redesign')

  const selectedDefinitionTypeLabel = definitionTypeLabels[valueTypeField.value] || definitionTypeLabels.string

  const savePropertyPath = useSavePropertyPath()

  function addAllowedValue() {
    if (newAllowedValueField.validate()) {
      return newAllowedValueRef.current?.focus()
    }

    allowedValuesField.update([...allowedValuesField.value, newAllowedValueField.value.trim()])
    newAllowedValueField.reset()
  }

  function removeAllowedValue(index: number) {
    allowedValuesField.update(allowedValuesField.value.filter((_, currentIndex) => currentIndex !== index))
    const focusElement = getFocusListItem(allowedValuesItemsRefs.current, index) || newAllowedValueRef

    allowedValuesItemsRefs.current.splice(index, 1)

    // ActionList needs to unmount to release the focus trap. setTimeout puts focus in the next rendering cycle.
    setTimeout(() => focusElement.current?.focus())
  }

  function focusFirstInvalidField(errors: FormErrors) {
    const refs = [
      {
        element: propertyNameRef.current,
        invalid: !!errors.propertyName,
      },
      {
        element: propertyDescriptionRef.current,
        invalid: !!errors.description,
      },
      {
        element: regexInputRef.current,
        invalid: !!errors.regex,
      },
      {
        element: newAllowedValueRef.current,
        invalid: !!errors.allowedValues,
      },
      {
        element: propertyStringDefaultValueRef.current,
        invalid: !!errors.defaultValue,
      },
      {
        element: propertySingleSelectDefaultValueRef.current,
        invalid: !!errors.defaultValue,
      },
      {
        element: propertyBooleanDefaultValueRef.current,
        invalid: !!errors.defaultValue,
      },
      {
        element: propertyMultiSelectDefaultValueRef.current,
        invalid: !!errors.defaultValue,
      },
    ]

    const firstInvalidItem = refs.find(item => item.element && item.invalid)
    firstInvalidItem?.element?.focus()
  }

  async function formCanBeSaved() {
    const validationErrors = await validateForm()

    if (validationErrors.allowedValues) {
      setFormError(validationErrors.allowedValues as SafeHTMLString)
      return false
    }

    if (Object.values(validationErrors).some(x => x)) {
      focusFirstInvalidField(validationErrors)
      return false
    }

    return true
  }

  async function saveDefinition(body: Omit<PropertyDefinition, 'source'>) {
    setFormError('' as SafeHTMLString)
    if (!(await formCanBeSaved())) {
      return
    }
    setSaving(true)

    if (!(await sudo())) {
      setFormError('Unauthorized' as SafeHTMLString)
      setSaving(false)
      return
    }

    const result = await verifiedFetchJSON(savePropertyPath, {
      method: 'POST',
      body,
    })

    if (result.ok) {
      setBanner(isEditing ? 'definition.updated.success' : 'definition.created.success')
      onSuccess(body.propertyName)
    } else {
      const responseBody = await result.json()
      setFormError((responseBody?.error || 'Something went wrong.') as SafeHTMLString)
      setSaving(false)
    }
  }

  const onDrop = ({dragMetadata, dropMetadata, isBefore}: OnDropArgs<string>) => {
    if (dragMetadata.id === dropMetadata?.id) {
      return
    }

    const items = allowedValuesField.value
    const reorderedOption = items.find(item => item === dragMetadata.id)!

    const newlyOrderedItems = items.reduce<string[]>((newItems, item) => {
      if (item === reorderedOption) {
        return newItems
      }

      if (item !== dropMetadata?.id) {
        newItems.push(item)
      } else if (isBefore) {
        newItems.push(reorderedOption, item)
      } else if (!isBefore) {
        newItems.push(item, reorderedOption)
      }

      return newItems
    }, [])

    allowedValuesField.update(newlyOrderedItems)
  }

  const allowableDefaultValues = isTrueFalse ? ['true', 'false'] : allowedValuesField.value

  const propertyNameValidationId = 'property-name-validation-error'
  const defaultValues = isMultiSelect ? (defaultValueField.value as string[]) : [defaultValueField.value]

  const propertyNameValidationResult = propertyNameField.validationError

  const defaultValueInvalid = !defaultValueField.validationError?.loading && !!defaultValueField.validationError?.error
  const defaultValueAriaAriaProp = {
    'aria-invalid': defaultValueInvalid,
    'aria-labelledby': 'property-default-value-label',
    'aria-describedby': `${
      defaultValueInvalid ? 'property-default-value-validation' : ''
    } property-default-value-caption`,
  }

  return (
    <>
      <div data-hpc data-testid="settings-page-content" className={styles.propertySettingsContainer}>
        <FormControl required disabled={isEditing} className={styles.propertyFormControl}>
          <FormControl.Label>Name</FormControl.Label>
          <TextInput
            block
            ref={propertyNameRef}
            aria-describedby={propertyNameField.validationError ? propertyNameValidationId : undefined}
            aria-invalid={!propertyNameField.isValid()}
            value={propertyNameField.value}
            onChange={e => propertyNameField.update(e.target.value)}
          />

          {propertyNameValidationResult && (
            <>
              <FormControl.Validation variant="error" id={propertyNameValidationId}>
                {propertyNameValidationResult.message}
              </FormControl.Validation>
              {!!propertyNameValidationResult?.orgConflicts?.usages.length && (
                <>
                  <FormControl.Caption>
                    See{' '}
                    <Link
                      inline
                      href="#"
                      onClick={e => {
                        e.preventDefault()
                        setShowOrgConflicts(true)
                      }}
                    >
                      organizations
                    </Link>{' '}
                    with this property
                  </FormControl.Caption>
                  {showOrgConflicts && (
                    <OrgConflictsDialog
                      title="Conflicts"
                      displayMessage="This property cannot be created because there are conflicting properties in this enterprise's organizations"
                      onClose={() => setShowOrgConflicts(false)}
                      orgConflicts={propertyNameValidationResult.orgConflicts}
                    />
                  )}
                </>
              )}
            </>
          )}
        </FormControl>

        <FormControl className={styles.propertyFormControl}>
          <FormControl.Label>Description</FormControl.Label>
          <Textarea
            block
            rows={4}
            resize="vertical"
            placeholder="A short description about this property"
            ref={propertyDescriptionRef}
            value={descriptionField.value}
            onChange={e => descriptionField.update(e.target.value)}
            onBlur={descriptionField.validate}
          />

          {descriptionField.validationError && (
            <FormControl.Validation variant="error">{descriptionField.validationError}</FormControl.Validation>
          )}
        </FormControl>

        <div className={styles.typeDropdownContainer}>
          <FormControl
            sx={{
              mb: isSingleSelect || isMultiSelect ? 3 : 0,
            }}
            disabled={isEditing}
            className={styles.typeFormControl}
          >
            <FormControl.Label>Type</FormControl.Label>
            <ActionMenu
              open={typeDropdownOpen}
              onOpenChange={open => {
                if (isEditing) return
                setTypeDropdownOpen(open)
              }}
            >
              <ActionMenu.Button
                id="type-dropdown-button"
                inactive={isEditing}
                aria-disabled={isEditing}
                aria-label={`Type: ${selectedDefinitionTypeLabel}`}
              >
                {selectedDefinitionTypeLabel}
              </ActionMenu.Button>
              <ActionMenu.Overlay>
                <ActionList selectionVariant="single">
                  {Object.entries(definitionTypeLabels).map(([key, label]) => (
                    <ActionList.Item
                      key={key}
                      onSelect={() => valueTypeField.update(key as ValueType)}
                      selected={valueTypeField.value === key}
                    >
                      {label}
                    </ActionList.Item>
                  ))}
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
          </FormControl>
        </div>

        {(isSingleSelect || isMultiSelect) && (
          <div className={styles.optionsContainer}>
            <FormControl className={styles.optionsFormControl}>
              <FormControl.Label htmlFor="option-input" visuallyHidden>
                Options
              </FormControl.Label>
              <div className={styles.optionsInputGroup}>
                <TextInput
                  block
                  id="option-input"
                  placeholder="Add option..."
                  ref={newAllowedValueRef}
                  aria-invalid={!!newAllowedValueField.validationError}
                  aria-describedby={
                    newAllowedValueField.validationError ? 'property-new-allowed-value-validation' : undefined
                  }
                  value={newAllowedValueField.value}
                  onChange={e => newAllowedValueField.update(e.target.value)}
                  // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
                  onKeyDown={e => e.key === 'Enter' && addAllowedValue()}
                />

                <Button onClick={addAllowedValue}>Add</Button>
              </div>
              {newAllowedValueField.validationError && (
                <FormControl.Validation id="property-new-allowed-value-validation" variant="error">
                  {newAllowedValueField.validationError}
                </FormControl.Validation>
              )}
            </FormControl>

            {allowedValuesField.value.length > 0 ? (
              <DragAndDrop
                items={allowedValuesField.value.map(value => {
                  return {id: value, title: value}
                })}
                onDrop={onDrop}
                style={{listStyleType: 'none', maxHeight: '500px', overflowY: 'auto'}}
                renderOverlay={({id: value}, index) => (
                  <DragAndDrop.Item
                    aria-label={value}
                    index={index}
                    id={value}
                    title={value}
                    key={value}
                    hideSortableItemTrigger
                    style={{borderTop: 'solid 1px var(--borderColor-default, var(--color-border-default))'}}
                    isDragOverlay
                  >
                    <AllowedValueItem
                      value={value}
                      isDefaultValue={defaultValues.includes(value)}
                      onDelete={() => removeAllowedValue(index)}
                      index={index}
                    />
                  </DragAndDrop.Item>
                )}
              >
                {allowedValuesField.value.map((value, index) => (
                  <DragAndDrop.Item
                    aria-label={value}
                    index={index}
                    id={value}
                    title={value}
                    key={value}
                    hideSortableItemTrigger
                    style={{borderTop: 'solid 1px var(--borderColor-default, var(--color-border-default))'}}
                  >
                    <AllowedValueItem
                      value={value}
                      isDefaultValue={defaultValues.includes(value)}
                      onDelete={() => removeAllowedValue(index)}
                      index={index}
                      setMenuAnchorRef={ref => (allowedValuesItemsRefs.current[index] = ref)}
                    />
                  </DragAndDrop.Item>
                ))}
              </DragAndDrop>
            ) : (
              <div className={styles.emptyOptionsMessage}>No options</div>
            )}
          </div>
        )}

        <div className={styles.additionalSettingsSection}>
          {isText && (
            <div>
              <FormControl>
                <FormControl.Label>Match regular expression</FormControl.Label>
                <Checkbox
                  checked={regexEnabledField.value}
                  onChange={() => regexEnabledField.update(!regexEnabledField.value)}
                  aria-label="Use regular expression"
                />
              </FormControl>
              {regexEnabled && (
                <>
                  <div className={styles.regexInputContainer}>
                    <RegexPatternInput
                      ref={regexInputRef}
                      onChange={value => regexField.update(value)}
                      value={regexField.value}
                      validationError={regexField.validationError}
                    />
                  </div>

                  <Button
                    ref={testRegexValuesRef}
                    onClick={() => setShowRegexTestValueDialog(true)}
                    className={styles.testRegexButton}
                  >
                    Test values…
                  </Button>
                  {showRegexTestValueDialog && (
                    <RegexTesterDialog
                      onDismiss={() => setShowRegexTestValueDialog(false)}
                      onRegexPatternChange={value => regexField.update(value)}
                      regexPattern={regexField.value}
                      regexPatternValidationError={regexField.validationError}
                      returnFocusRef={testRegexValuesRef}
                    />
                  )}
                </>
              )}
            </div>
          )}

          <FormControl>
            <Checkbox
              checked={repoActorsEditingAllowedField.value}
              onChange={() => repoActorsEditingAllowedField.update(!repoActorsEditingAllowedField.value)}
            />
            <FormControl.Label>Allow repository actors to set this property</FormControl.Label>
            <FormControl.Caption>
              Repository users and apps with the repository-level &quot;custom properties&quot; fine-grained permission
              can set and update the value for their repository.
            </FormControl.Caption>
          </FormControl>

          <div>
            <FormControl>
              <Checkbox checked={requiredField.value} onChange={() => requiredField.update(!requiredField.value)} />
              <FormControl.Label>Require this property for all repositories</FormControl.Label>
              <FormControl.Caption>
                Repositories that don&apos;t have an explicit value for this property will inherit the default value.
              </FormControl.Caption>
            </FormControl>
            <div className={styles.optionsInputGroup}>
              {requiredField.value && (
                <FormControl className={styles.defaultValueFormControl}>
                  <FormControl.Label id="property-default-value-label">Default value *</FormControl.Label>
                  {isMultiSelect && (
                    <div className={styles.selectPanelContainer}>
                      {editingRedesignEnabled ? (
                        <CustomPropertyMultiSelectPanel
                          anchorRef={propertyMultiSelectDefaultValueRef}
                          propertyValue={defaultValueField.value as string[]}
                          mixed={false}
                          onChange={values => defaultValueField.update(values)}
                          propertyName={propertyNameField.value}
                          allowedValues={allowableDefaultValues}
                          defaultValue={null}
                          anchorProps={defaultValueAriaAriaProp}
                        />
                      ) : (
                        <OldCustomPropertyMultiSelectPanel
                          anchorRef={propertyMultiSelectDefaultValueRef}
                          propertyValue={defaultValueField.value as string[]}
                          mixed={false}
                          onChange={values => defaultValueField.update(values)}
                          propertyName={propertyNameField.value}
                          allowedValues={allowableDefaultValues}
                          defaultValue={null}
                          anchorProps={defaultValueAriaAriaProp}
                        />
                      )}
                    </div>
                  )}

                  {isSingleSelect && (
                    <div className={styles.selectPanelContainer}>
                      {editingRedesignEnabled ? (
                        <CustomPropertySingleSelectPanel
                          anchorRef={propertySingleSelectDefaultValueRef}
                          propertyValue={defaultValueField.value as string}
                          mixed={false}
                          onChange={values => defaultValueField.update(values)}
                          propertyName={propertyNameField.value}
                          allowedValues={allowableDefaultValues}
                          defaultValue={null}
                          anchorProps={defaultValueAriaAriaProp}
                        />
                      ) : (
                        <OldCustomPropertySingleSelectPanel
                          anchorRef={propertySingleSelectDefaultValueRef}
                          propertyValue={defaultValueField.value as string}
                          mixed={false}
                          onChange={values => defaultValueField.update(values)}
                          propertyName={propertyNameField.value}
                          allowedValues={allowableDefaultValues}
                          defaultValue={null}
                          anchorProps={defaultValueAriaAriaProp}
                        />
                      )}
                    </div>
                  )}

                  {isTrueFalse && (
                    <div className={styles.selectPanelContainer}>
                      {editingRedesignEnabled ? (
                        <CustomPropertyBooleanSelectPanel
                          anchorRef={propertySingleSelectDefaultValueRef}
                          propertyValue={defaultValueField.value as string}
                          mixed={false}
                          onChange={defaultValueField.update}
                          propertyName={propertyNameField.value}
                          defaultValue={null}
                          anchorProps={defaultValueAriaAriaProp}
                        />
                      ) : (
                        <OldCustomPropertySingleSelectPanel
                          anchorRef={propertySingleSelectDefaultValueRef}
                          propertyValue={defaultValueField.value as string}
                          mixed={false}
                          onChange={defaultValueField.update}
                          propertyName={propertyNameField.value}
                          allowedValues={['true', 'false']}
                          defaultValue={null}
                          anchorProps={defaultValueAriaAriaProp}
                        />
                      )}
                    </div>
                  )}

                  {isText && (
                    <TextInput
                      block
                      value={defaultValueField.value}
                      ref={propertyStringDefaultValueRef}
                      onChange={e => defaultValueField.update(e.target.value)}
                      {...defaultValueAriaAriaProp}
                    />
                  )}

                  {!defaultValueField.validationError?.loading && defaultValueField.validationError?.error && (
                    <FormControl.Validation
                      id="property-default-value-validation"
                      variant="error"
                      className={styles.validationFeedback}
                    >
                      {defaultValueField.validationError.error}
                    </FormControl.Validation>
                  )}
                  <FormControl.Caption id="property-default-value-caption">
                    This is the default value that will be set for this property. Changing it has immediate effect,
                    although on large organizations it may take minutes to be available in search results.
                  </FormControl.Caption>
                </FormControl>
              )}
            </div>
          </div>
        </div>
      </div>
      <div className={styles.formActionsContainer}>
        <Button
          variant="primary"
          disabled={saving}
          onClick={() =>
            saveDefinition({
              propertyName: propertyNameField.value,
              valueType: valueTypeField.value,
              required: requiredField.value,
              defaultValue: requiredField.value ? defaultValueField.value : null,
              description: descriptionField.value.trim() || null,
              allowedValues: isSingleSelect || isMultiSelect ? allowedValuesField.value : null,
              valuesEditableBy: repoActorsEditingAllowedField.value ? 'org_and_repo_actors' : 'org_actors',
              regex: (regexEnabled && regexField.value) || null,
            })
          }
        >
          {saving ? 'Saving...' : 'Save property'}
        </Button>

        <Button onClick={onCancel}>Cancel</Button>
      </div>
    </>
  )
}

function AllowedValueItem({
  value,
  isDefaultValue,
  onDelete,
  index,
  setMenuAnchorRef,
}: {
  value: string
  isDefaultValue: boolean
  onDelete(): void
  index: number
  setMenuAnchorRef?: (ref: React.RefObject<HTMLButtonElement>) => void
}) {
  const {openMoveDialog} = useDragAndDrop()
  const editButtonRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    setMenuAnchorRef?.(editButtonRef)
  }, [setMenuAnchorRef])

  return (
    <div className={styles.allowedValueItem}>
      <div className={styles.allowedValueContent}>
        <DragAndDrop.DragTrigger style={{marginRight: 0}} />
        {value}
        {isDefaultValue && <Label variant="accent">Default</Label>}
      </div>
      <div>
        <ActionMenu anchorRef={editButtonRef}>
          <ActionMenu.Anchor>
            <IconButton
              icon={KebabHorizontalIcon}
              variant="invisible"
              aria-label={`More options for ${value}`}
              description="More options"
            />
          </ActionMenu.Anchor>

          <ActionMenu.Overlay>
            <ActionList>
              <ActionList.Item
                onSelect={() => openMoveDialog(value, index, editButtonRef)}
                aria-label={`Advanced move ${value}...`}
              >
                <ActionList.LeadingVisual>
                  <GrabberIcon />
                </ActionList.LeadingVisual>
                Advanced Move...
              </ActionList.Item>
              <ActionList.Item variant="danger" onSelect={onDelete} aria-label={`Delete option ${value}`}>
                Delete
              </ActionList.Item>
            </ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>
      </div>
    </div>
  )
}

function getFocusListItem<T>(items: T[], index: number): T | null {
  const prevEl = items[index - 1]
  const nextEl = items[index + 1]

  return nextEl || prevEl || null
}

import {PlusIcon} from '@primer/octicons-react'
import {Box, Button} from '@primer/react'
import {IssueFieldPicker, type IssueField} from '@github-ui/item-picker/IssueFieldPicker'
import {graphql} from 'relay-runtime'
import type {FieldsSectionFragment$key} from './__generated__/FieldsSectionFragment.graphql'
import {useFragment} from 'react-relay'
import type React from 'react'
import {useCallback, forwardRef, useState, useMemo, useEffect} from 'react'
import type {FieldsSectionFieldValues$key} from './__generated__/FieldsSectionFieldValues.graphql'
import {IssueFieldSingleSelectEditor, IssueFieldTextEditor} from './FieldEditors'
import {
  IssueSingleSelectFieldPicker,
  type IssueFieldSingleSelectOption,
} from '@github-ui/item-picker/IssueSingleSelectFieldPicker'
import {
  isIssueFieldWithUnsavedValue,
  isSingleSelectField,
  isSingleSelectFieldWithValue,
  isTextField,
  type IssueFieldWithUnsavedValue,
} from '../../utils/issue-field-helper'

export type CreateIssueFieldsSectionProps = {owner: string; shortcutEnabled: boolean}

export function CreateIssueFieldsSection({owner, shortcutEnabled}: CreateIssueFieldsSectionProps) {
  const isReadonly = false
  const [fieldsSet, setFieldsSet] = useState<string[]>([])
  const [activeSingleSelectField, setActiveSingleSelectField] = useState<IssueField | null>(null)
  const [fields, setFields] = useState<IssueFieldWithUnsavedValue[]>([])

  const anchorElement = useMemo(() => {
    // eslint-disable-next-line react/display-name
    return (anchorProps: React.HTMLAttributes<HTMLElement>, ref?: React.Ref<HTMLButtonElement>) => (
      <AddIssueFieldButton anchorProps={anchorProps} ref={ref} />
    )
  }, [])

  const onIssueFieldSelected = useCallback(async (_selectedFields: IssueField[]) => {
    if (_selectedFields.length > 0 && _selectedFields[0]?.id) {
      const field = _selectedFields[0]
      if (isSingleSelectField(field)) {
        // for single select field, we don't create a value immediately, but instead we show
        // a picker to select a value
        setActiveSingleSelectField(field)
      } else if (isTextField(field)) {
        setFields(prevFields => {
          const newFields = [...prevFields]
          if (field.name && !newFields.some(f => f.field.name === field.name)) {
            newFields.push({field, value: ''})
          }
          return newFields
        })
      }

      if (field.name) {
        setFieldsSet(prevFieldsSet => {
          const newFieldsSet = [...prevFieldsSet]
          if (field.name && !newFieldsSet.includes(field.name)) {
            newFieldsSet.push(field.name)
          }
          return newFieldsSet
        })
      }
    }
  }, [])

  const onIssueSingleSelectValueSelected = useCallback(
    async (selectedOption: IssueFieldSingleSelectOption | null) => {
      if (!activeSingleSelectField || !isSingleSelectField(activeSingleSelectField)) return
      setFields(prevFields => {
        const newFields = [...prevFields]
        if (activeSingleSelectField.name && !newFields.some(f => f.field.name === activeSingleSelectField.name)) {
          newFields.push({
            field: activeSingleSelectField,
            value: selectedOption,
          })
        }
        return newFields
      })
      setActiveSingleSelectField(null)
    },
    [activeSingleSelectField],
  )

  const onCommitTextField = useCallback((fieldId: string, value: string) => {
    setFields(prevFields => {
      return prevFields.map(field => {
        if (isIssueFieldWithUnsavedValue(field) && field.field.id === fieldId) {
          return {...field, value}
        }
        return field
      })
    })
  }, [])

  const onCommitSingleSelectField = useCallback((fieldId: string, value: IssueFieldSingleSelectOption | null) => {
    setFields(prevFields => {
      return prevFields.map(field => {
        if (isSingleSelectFieldWithValue(field) && field.field.id === fieldId) {
          return {...field, value}
        }
        return field
      })
    })
  }, [])

  return (
    <>
      {fields.map((field, index) => {
        const isLastItem = index === fields.length - 1
        if (isIssueFieldWithUnsavedValue(field)) {
          return (
            <IssueFieldTextEditor
              key={field.field.name}
              fieldId={field.field.id || ''}
              fieldName={field.field.name || ''}
              initialValue={field.value || ''}
              onCommit={onCommitTextField}
              hideDivider={isLastItem}
            />
          )
        } else if (isSingleSelectFieldWithValue(field)) {
          return (
            <IssueFieldSingleSelectEditor
              key={field.field.name}
              fieldId={field.field.id || ''}
              fieldName={field.field.name || ''}
              initialValue={
                field.value
                  ? {
                      name: field.value.name || '',
                      color: field.value.color || '',
                      description: field.value.description || '',
                    }
                  : null
              }
              onCommit={onCommitSingleSelectField}
              hideDivider={isLastItem}
            />
          )
        }
      })}
      {activeSingleSelectField?.id && (
        <IssueSingleSelectFieldPicker
          fieldId={activeSingleSelectField.id}
          selectedOption={null}
          onSelectionChange={onIssueSingleSelectValueSelected}
          readonly={false}
          isLazy={false}
          shortcutEnabled
          anchorElement={anchorElement}
        />
      )}
      <IssueFieldPicker
        owner={owner}
        fieldsSet={fieldsSet}
        onSelectionChange={onIssueFieldSelected}
        shortcutEnabled={shortcutEnabled}
        readonly={isReadonly}
        anchorElement={anchorElement}
        insidePortal={false}
      />
    </>
  )
}

export type EditIssueFieldsSectionProps = {
  onIssueUpdate?: () => void
  singleKeyShortcutsEnabled: boolean
  issue: FieldsSectionFragment$key
  insideSidePanel?: boolean
}

export function EditIssueFieldsSection({issue, singleKeyShortcutsEnabled}: EditIssueFieldsSectionProps) {
  const [activeSingleSelectField, setActiveSingleSelectField] = useState<IssueField | null>(null)
  const [fieldsSet, setFieldsSet] = useState<string[]>([])

  // TODO issue_fields
  const isReadonly = false

  const data = useFragment(
    graphql`
      fragment FieldsSectionFragment on Issue {
        id
        repository {
          owner {
            login
          }
        }
        ...FieldsSectionFieldValues
      }
    `,
    issue,
  )
  const {
    repository: {
      owner: {login: owner},
    },
  } = data

  const onIssueFieldSelected = useCallback(async (_selectedFields: IssueField[]) => {
    if (_selectedFields.length > 0 && _selectedFields[0]?.id) {
      const field = _selectedFields[0]
      if (field.dataType === 'SINGLE_SELECT') {
        // for single select field, we don't create a value immediately, but instead we show
        // a picker to select a value
        setActiveSingleSelectField(field)
      } else {
        // TODO issue_field call set field value mutation
      }
      if (field.name) {
        setFieldsSet(prevFieldsSet => {
          const newFieldsSet = [...prevFieldsSet]
          if (field.name && !newFieldsSet.includes(field.name)) {
            newFieldsSet.push(field.name)
          }
          return newFieldsSet
        })
      }
    }
  }, [])

  const onIssueSingleSelectValueSelected = useCallback(
    async (selectedOption: IssueFieldSingleSelectOption | null) => {
      if (activeSingleSelectField?.id && selectedOption) {
        // TODO issue_field call set field value mutation
      }
      setActiveSingleSelectField(null)
    },
    [activeSingleSelectField],
  )

  const anchorElement = useMemo(() => {
    // eslint-disable-next-line react/display-name
    return (anchorProps: React.HTMLAttributes<HTMLElement>, ref?: React.Ref<HTMLButtonElement>) => (
      <AddIssueFieldButton anchorProps={anchorProps} ref={ref} />
    )
  }, [])

  return (
    <>
      <IssueFields issue={data} fieldsSet={fieldsSet} setFieldsSet={setFieldsSet} />
      {activeSingleSelectField?.id && (
        <IssueSingleSelectFieldPicker
          fieldId={activeSingleSelectField.id}
          selectedOption={null}
          onSelectionChange={onIssueSingleSelectValueSelected}
          readonly={false}
          isLazy={false}
          shortcutEnabled
          anchorElement={anchorElement}
        />
      )}
      <IssueFieldPicker
        owner={owner}
        fieldsSet={fieldsSet}
        onSelectionChange={onIssueFieldSelected}
        shortcutEnabled={singleKeyShortcutsEnabled}
        readonly={isReadonly}
        anchorElement={anchorElement}
        insidePortal={false}
      />
    </>
  )
}

function IssueFields({
  issue,
  fieldsSet,
  setFieldsSet,
}: {
  issue: FieldsSectionFieldValues$key
  fieldsSet: string[]
  setFieldsSet: React.Dispatch<React.SetStateAction<string[]>>
}) {
  const data = useFragment(
    graphql`
      fragment FieldsSectionFieldValues on Issue {
        id
        issueFieldValues(first: 25) {
          nodes {
            ... on IssueFieldTextValue {
              field {
                ... on IssueFieldText {
                  id
                  name
                  dataType
                }
              }
              value
            }
            ... on IssueFieldSingleSelectValue {
              field {
                ... on IssueFieldSingleSelect {
                  name
                  dataType
                }
              }
              name
              color
              description
            }
          }
        }
      }
    `,
    issue,
  )

  const filteredFieldValues = (data.issueFieldValues?.nodes || []).filter(fv => !!fv && fv.field)

  const filteredFieldsNames = filteredFieldValues.map(fv => fv?.field?.name || '')

  useEffect(() => {
    if (fieldsSet.join(',') !== filteredFieldsNames.join(',') && filteredFieldsNames.length > 0) {
      setFieldsSet(filteredFieldsNames)
    }
  }, [fieldsSet, filteredFieldsNames, setFieldsSet])

  // eslint-disable-next-line unused-imports/no-unused-vars
  const onCommitTextField = useCallback((fieldId: string, value: string) => {
    // TODO issue_field call set field value mutation
  }, [])

  // eslint-disable-next-line unused-imports/no-unused-vars
  const onCommitSingleSelectField = useCallback((fieldId: string, value: IssueFieldSingleSelectOption | null) => {
    // TODO issue_field call set field value mutation
  }, [])

  const fieldValues = filteredFieldValues.map((fieldValue, index) => {
    if (!fieldValue || !fieldValue.field) return null
    const isLastItem = index === filteredFieldValues.length - 1

    if (fieldValue.field && fieldValue.field.dataType === 'TEXT') {
      return (
        <IssueFieldTextEditor
          key={fieldValue.field.name}
          fieldId={fieldValue.field.id || ''}
          fieldName={fieldValue.field.name || ''}
          initialValue={fieldValue.value || ''}
          onCommit={onCommitTextField}
          hideDivider={isLastItem}
        />
      )
    } else if (fieldValue.field.dataType === 'SINGLE_SELECT') {
      return (
        <IssueFieldSingleSelectEditor
          key={fieldValue.field.name}
          fieldId={fieldValue.field.id || ''}
          fieldName={fieldValue.field.name || ''}
          initialValue={{
            name: fieldValue.name || '',
            color: fieldValue.color || '',
            description: fieldValue.description || '',
          }}
          onCommit={onCommitSingleSelectField}
          hideDivider={isLastItem}
        />
      )
    } else {
      return null
    }
  })

  return <>{fieldValues}</>
}

const AddIssueFieldButton = forwardRef<
  HTMLButtonElement,
  {
    anchorProps?: React.HTMLAttributes<HTMLElement> | undefined
  }
>((props, ref) => {
  const {anchorProps} = props
  return (
    <Box
      sx={{
        marginTop: 2,
        marginBottom: 3,
        position: 'relative',
        ':after': {
          content: '""',
          position: 'absolute',
          height: '1px',
          bottom: '-8px',
          left: '8px',
          bg: 'border.muted',
          width: 'calc(100% - 8px)',
        },
      }}
    >
      <Button trailingVisual={PlusIcon} size="small" ref={ref} {...anchorProps} sx={{width: '100%', ml: 2, mr: 2}}>
        Add field
      </Button>
    </Box>
  )
})
AddIssueFieldButton.displayName = 'AddIssueFieldButton'

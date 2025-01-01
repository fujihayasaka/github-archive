import {useState, useCallback, useMemo} from 'react'
import {Box, TextInput} from '@primer/react'
import type {IssueFieldSingleSelectOption} from '@github-ui/item-picker/IssueSingleSelectFieldPicker'
import {IssueSingleSelectFieldPicker} from '@github-ui/item-picker/IssueSingleSelectFieldPicker'
import {SectionHeader} from '../SectionHeader'
import {IssueFieldSingleSelectValueToken} from './IssueFieldSingleSelectValueToken'
import {Section} from '../Section'

type IssueFieldCommentEditorProps = {fieldId: string; fieldName: string; hideDivider: boolean}

type IssueFieldTextEditorProps = IssueFieldCommentEditorProps & {
  initialValue: string
  onCommit: (fieldId: string, value: string) => void
}

export const IssueFieldTextEditor = ({
  fieldId,
  fieldName,
  initialValue,
  onCommit,
  hideDivider,
}: IssueFieldTextEditorProps) => {
  const [text, setText] = useState(initialValue || '')

  const onBlur = () => {
    onCommit(fieldId, text)
  }

  return (
    <Section sectionHeader={<SectionHeader title={fieldName} readonly />} hideDivider={hideDivider}>
      <TextInput
        aria-label={`The value for the ${fieldName} field`}
        value={text}
        onChange={e => setText(e.target.value)}
        onBlur={onBlur}
        sx={{ml: 2, width: '100%'}}
      />
    </Section>
  )
}

type IssueFieldSingleSelectEditorProps = IssueFieldCommentEditorProps & {
  initialValue: {
    name: string
    color: string
    description?: string
  } | null
  onCommit: (fieldId: string, value: IssueFieldSingleSelectOption | null) => void
}

export const IssueFieldSingleSelectEditor = ({
  fieldId,
  fieldName,
  initialValue,
  onCommit,
  hideDivider,
}: IssueFieldSingleSelectEditorProps) => {
  const onSelectionChanged = useCallback(
    (selectedOption: IssueFieldSingleSelectOption | null) => {
      onCommit(fieldId, selectedOption)
    },
    [fieldId, onCommit],
  )

  const sectionHeader = useMemo(() => {
    return (
      <IssueSingleSelectFieldPicker
        fieldId={fieldId}
        selectedOption={initialValue ? initialValue.name : null}
        onSelectionChange={onSelectionChanged}
        anchorElement={(anchorProps, ref) => (
          <SectionHeader title={fieldName || ''} buttonProps={anchorProps} ref={ref} />
        )}
        readonly={false}
        isLazy
        shortcutEnabled
      />
    )
  }, [fieldId, fieldName, initialValue, onSelectionChanged])

  return (
    <Section sectionHeader={sectionHeader} hideDivider={hideDivider}>
      <Box sx={{ml: 2, mt: 1}}>
        <IssueFieldSingleSelectValueToken
          name={initialValue?.name || ''}
          color={initialValue?.color || ''}
          getTooltipText={isTextTruncated => (isTextTruncated ? initialValue?.description ?? '' : undefined)}
        />
      </Box>
    </Section>
  )
}

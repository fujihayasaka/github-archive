import type {IssueField} from '@github-ui/item-picker/IssueFieldPicker'
import type {IssueFieldSingleSelectOption} from '@github-ui/item-picker/IssueSingleSelectFieldPicker'

// type that is used when we add a text field during issue creation
type IssueTextFieldWithValue = {
  field: IssueField & {dataType?: 'TEXT'}
  value: string
}

// type that is used when we add a single select field during issue creation
type IssueSingleSelectFieldWithValue = {
  field: IssueField & {dataType?: 'SINGLE_SELECT'}
  value: IssueFieldSingleSelectOption | null
}

export type IssueFieldWithUnsavedValue = IssueTextFieldWithValue | IssueSingleSelectFieldWithValue

export function isTextField(field: IssueField): field is IssueField & {dataType: 'TEXT'} {
  return field.dataType === 'TEXT'
}

export function isSingleSelectField(field: IssueField): field is IssueField & {dataType: 'SINGLE_SELECT'} {
  return field.dataType === 'SINGLE_SELECT'
}

export function isIssueFieldWithUnsavedValue(field: IssueFieldWithUnsavedValue): field is IssueTextFieldWithValue {
  return isTextField(field.field)
}

export function isSingleSelectFieldWithValue(
  field: IssueFieldWithUnsavedValue,
): field is IssueSingleSelectFieldWithValue {
  return isSingleSelectField(field.field) && field.value !== null
}

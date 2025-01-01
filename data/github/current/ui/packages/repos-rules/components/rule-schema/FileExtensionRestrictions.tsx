import type {RegisteredRuleSchemaComponent} from '../../types/rules-types'
import {RestrictHelper} from './RestrictHelper'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'

export function FileExtensionRestrictions({value, onValueChange, readOnly}: RegisteredRuleSchemaComponent) {
  const {file_extension_and_path_limits: fileExtensionAndPathLimits} = useFeatureFlags()
  return (
    <RestrictHelper
      value={value as string[]}
      onValueChange={onValueChange}
      readOnly={readOnly}
      boxName="Restricted file extensions"
      buttonName="Add file extension"
      shortButtonName="File extension"
      subtitle="Commits that include files with the specified file extension will be rejected."
      label="File extension"
      examples="Examples: `bin`, `exe`"
      blankslate="No file extensions"
      validationError={(extension: string) => {
        if (extension.includes('\\') || extension.includes('/') || extension.includes('*')) {
          return 'File extension cannot contain \\, /, or *'
        }
        if (fileExtensionAndPathLimits && extension.length > 200) {
          return 'File extension is too long. Maximum length is 200 characters'
        }
        return ''
      }}
      prefix="*."
    />
  )
}

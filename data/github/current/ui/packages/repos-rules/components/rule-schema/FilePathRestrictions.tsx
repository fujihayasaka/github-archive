import type {RegisteredRuleSchemaComponent} from '../../types/rules-types'
import {RestrictHelper} from './RestrictHelper'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'

export function FilePathRestrictions({value, onValueChange, readOnly}: RegisteredRuleSchemaComponent) {
  const {file_extension_and_path_limits: fileExtensionAndPathLimits} = useFeatureFlags()
  return (
    <RestrictHelper
      value={value as string[]}
      onValueChange={onValueChange}
      readOnly={readOnly}
      boxName="Restricted file paths"
      buttonName="Add file path"
      subtitle="Commits that include changes to files in the specified file path will be rejected."
      label="File path"
      examples="Example: `.github/**/*`"
      blankslate="No file paths"
      validationError={(path: string) => {
        if (fileExtensionAndPathLimits && path.length > 200) {
          return 'File path is too long. Maximum length is 200 characters'
        }
        return ''
      }}
    />
  )
}

import {SingleSelectIcon, TypographyIcon} from '@primer/octicons-react'
import {Box} from '@primer/react'
import {colorNames, useNamedColor} from '@github-ui/use-named-color'
import type {IssueFieldDataType} from './__generated__/IssueFieldPickerIssueField.graphql'
import type {IssueFieldSingleSelectOptionColor} from './__generated__/IssueSingleSelectFieldPickerOption.graphql'

export function createIssueFieldPickerItemLeadingVisual(dataType: IssueFieldDataType) {
  if (dataType === 'TEXT') {
    return TypographyIcon
  } else if (dataType === 'SINGLE_SELECT') {
    return SingleSelectIcon
  } else {
    return undefined
  }
}

export const createIssueSingleSelectFieldPickerItemLeadingVisual = (color: IssueFieldSingleSelectOptionColor) => {
  return function IssueSingleSelectFieldPickerItemLeadingVisual() {
    const effectiveColor = colorNames.find(c => c === color)
    const {bg, accent} = useNamedColor(effectiveColor)
    return (
      <Box
        sx={{
          bg,
          borderColor: accent,
          borderWidth: 2,
          borderStyle: 'solid',
          width: 12,
          height: 12,
          borderRadius: 8,
          flexShrink: 0,
        }}
      />
    )
  }
}

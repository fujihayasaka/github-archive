import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'

export function buildLabel({name}: {name: string}) {
  return {
    ' $fragmentType': 'LabelPickerLabel' as const,
    id: mockRelayId(),
    name,
    nameHTML: name,
    description: '',
    color: 'ff0000',
    url: `/${name}`,
  }
}

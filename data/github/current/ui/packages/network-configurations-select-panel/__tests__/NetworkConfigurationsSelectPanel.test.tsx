import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {NetworkConfigurationsSelectPanel} from '../NetworkConfigurationsSelectPanel'
import {getNetworkConfigurationsSelectPanelProps} from '../test-utils/mock-data'
import {ReadOnlyState} from '../helper'

test('Renders the NetworkConfigurationsSelectPanel', () => {
  const props = getNetworkConfigurationsSelectPanelProps()
  render(<NetworkConfigurationsSelectPanel {...props} />)
  expect(screen.getByRole('article')).toHaveTextContent('Network configurations')
})

test('Displays warning when isReadonly is ReadonlyWithPublicIPRunner', () => {
  const props = getNetworkConfigurationsSelectPanelProps()
  props.isReadonly = ReadOnlyState.ReadonlyWithPublicIPRunner
  render(<NetworkConfigurationsSelectPanel {...props} />)
  expect(screen.getByText(/This group contains a runner using a public IP/i)).toBeInTheDocument()
})

test('Does not display warning when isReadonly is Editable', () => {
  const props = getNetworkConfigurationsSelectPanelProps()
  props.isReadonly = ReadOnlyState.Editable
  render(<NetworkConfigurationsSelectPanel {...props} />)
  expect(screen.queryByText(/This group contains a runner using a public IP/i)).not.toBeInTheDocument()
})

test('Does not display warning when isReadonly is ReadOnly', () => {
  const props = getNetworkConfigurationsSelectPanelProps()
  props.isReadonly = ReadOnlyState.Readonly
  render(<NetworkConfigurationsSelectPanel {...props} />)
  expect(screen.queryByText(/This group contains a runner using a public IP/i)).not.toBeInTheDocument()
})

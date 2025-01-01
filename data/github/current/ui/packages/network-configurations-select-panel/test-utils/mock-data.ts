import type {NetworkConfigurationsSelectPanelProps} from '../NetworkConfigurationsSelectPanel'
import {ReadOnlyState} from '../helper'

export function getNetworkConfigurationsSelectPanelProps(): NetworkConfigurationsSelectPanelProps {
  return {
    networkConfigurations: [],
    selectedNetworkConfig: undefined,
    isReadonly: ReadOnlyState.Editable,
    isUpdate: false,
    formId: '',
  }
}

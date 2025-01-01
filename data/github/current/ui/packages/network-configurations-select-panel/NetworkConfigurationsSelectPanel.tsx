import {Heading, Link, FormControl, Button, SelectPanel} from '@primer/react'
import {useState, useEffect} from 'react'
import {AlertIcon, TriangleDownIcon} from '@primer/octicons-react'
import {NetworkConfigurationConsts} from './constants/network-configurations-consts'
import {requestSubmit} from '@github-ui/form-utils'
import {NetworkConfiguration, ComputeService} from '@github-ui/network-configurations'
import type {ActionListItemInput} from '@primer/react/deprecated'
import {ReadOnlyState} from './helper'

export interface NetworkConfigurationsSelectPanelProps {
  networkConfigurations: NetworkConfiguration[]
  selectedNetworkConfig?: NetworkConfiguration | undefined
  isReadonly: ReadOnlyState
  isUpdate: boolean
  formId: string
}

interface NetworkConfigurationSelectItem {
  id: string
  text: string
  selected?: boolean
}

export function NetworkConfigurationsSelectPanel({
  networkConfigurations,
  selectedNetworkConfig,
  isReadonly,
  isUpdate,
  formId,
}: NetworkConfigurationsSelectPanelProps) {
  networkConfigurations = networkConfigurations ?? []
  const noNetworkConfig = new NetworkConfiguration('-1', 'No configuration', '', ComputeService.Actions, '', [], [])
  networkConfigurations = [noNetworkConfig, ...networkConfigurations]
  const currentNetworkConfig = isUpdate && selectedNetworkConfig ? selectedNetworkConfig : noNetworkConfig

  const currentNetworkConfigItem = {
    id: currentNetworkConfig.id,
    text: currentNetworkConfig.name,
  }

  const [selected, setSelected] = useState(currentNetworkConfigItem)
  const currentNetworkConfigIsDisabled = isUpdate && currentNetworkConfig.computeService !== ComputeService.Actions
  const [shouldSubmit, setShouldSubmit] = useState(false)
  const [searchText, setSearchText] = useState('')
  const [open, setOpen] = useState(false)

  const filtered_networks = networkConfigurations.filter(
    item => !searchText || (item?.name ?? '').toLowerCase().includes(searchText.toLowerCase()),
  )

  const disabled_item = {
    text: currentNetworkConfig.name,
    groupId: '0',
    showDivider: true,
    selected: currentNetworkConfig.id === selected.id,
  }

  const grouped_network_item = {groupId: '0', header: {title: 'Disabled configuration'}}
  const filtered_network_items = filtered_networks
    .filter(item => item.computeService === ComputeService.Actions)
    .map(item => ({
      id: item.id,
      text: item.name,
      selected: item.id === selected.id,
    }))

  const network_items = currentNetworkConfigIsDisabled
    ? [...filtered_network_items, disabled_item]
    : filtered_network_items

  const onSelectChange = (item: NetworkConfigurationSelectItem) => {
    setSelected(item)
    const inputElement = document.querySelector('.js-network-configuration-selector') as HTMLInputElement
    if (inputElement) {
      inputElement.value = String(item.id)
      const event = new Event('change', {bubbles: true})
      inputElement.dispatchEvent(event)
    }
    if (item.id === currentNetworkConfig.id) return
    if (isUpdate) setShouldSubmit(true)
  }

  useEffect(() => {
    if (typeof document === 'undefined') {
      // Bail during server-side rendering since none of this is used then.
      return
    }
    if (isUpdate && shouldSubmit) {
      const form = document.getElementById(formId) as HTMLFormElement
      requestSubmit(form)
      setShouldSubmit(false)
    }
  }, [formId, isUpdate, shouldSubmit])

  const NoResultsMessage: {variant: 'empty'; title: string; body: string} = {
    variant: 'empty',
    title: 'No network configuration found',
    body: 'Try a different search term',
  }

  return (
    <article>
      <Heading as="h3" sx={{fontSize: 3, fontWeight: 'normal'}}>
        {NetworkConfigurationConsts.networkConfigurations}
      </Heading>
      <p className="color-fg-muted mb-2">
        {NetworkConfigurationConsts.networkConfigurationsDescription}{' '}
        <Link inline href={NetworkConfigurationConsts.learnMoreLink}>
          {NetworkConfigurationConsts.learnMore}
        </Link>
      </p>
      <FormControl id="network-configuration-select-panel">
        <FormControl.Label visuallyHidden>Network Configurations Select Panel</FormControl.Label>
        <SelectPanel
          title="Select network configuration"
          placeholder="Search"
          renderAnchor={props => (
            <Button {...props} trailingVisual={TriangleDownIcon} disabled={isReadonly !== ReadOnlyState.Editable}>
              {selected.text}
            </Button>
          )}
          items={network_items}
          selected={network_items.find(item => item.selected)}
          onSelectedChange={(selectedItem: ActionListItemInput | undefined) => {
            if (selectedItem) onSelectChange(selectedItem as NetworkConfigurationSelectItem)
          }}
          groupMetadata={currentNetworkConfigIsDisabled ? [grouped_network_item] : []}
          onOpenChange={setOpen}
          onFilterChange={filteredText => {
            setSearchText(filteredText)
          }}
          open={open}
          message={network_items.length === 0 ? NoResultsMessage : undefined}
          onCancel={() => {
            setOpen(false)
          }}
        />
        {currentNetworkConfigIsDisabled && (
          <FormControl.Validation variant="error">This network configuration is disabled</FormControl.Validation>
        )}
        {isReadonly === 2 && (
          <FormControl.Caption className="fgColor-attention">
            <AlertIcon size={16} /> This group contains a runner using a public IP and cannot be assigned a network
            configuration.
          </FormControl.Caption>
        )}
      </FormControl>
      <input
        type="text"
        name="network_config_id"
        className="js-network-configuration-selector"
        value={selected.id}
        hidden
        readOnly
      />
    </article>
  )
}

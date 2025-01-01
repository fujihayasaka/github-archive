import type React from 'react'
import {useState} from 'react'

import {Box, Link, ToggleSwitch, type BetterSystemStyleObject} from '@primer/react'
import Table from './Table'
import Header from './table/Header'
import Row, {type RowProps} from './table/Row'
import MultipleSelect from './dropdown/MultipleSelect'
import SingleSelect from './dropdown/SingleSelect'
import {
  defaultOption,
  defaultPrefix,
  actionsDropdownOptions,
  actionsDisplayOptions,
  actionsDropdownVariants,
  vulnerabilityDropdownOptions,
  vulnerabilityDisplayOptions,
  digestOptions,
  getSelectedOptionsAndVariants,
  actionsDisplayVariants,
} from '../helpers/selectors'
import {Sections} from '../components/State'
import type {ActionProps} from './ActionProps'

const actionsRow: RowProps = {
  title: 'Actions',
}

const dependabotAlertsRow: RowProps = {
  title: 'Dependabot alerts: New vulnerabilities',
  separator: false,
}

const emailWeeklyDigestRow: RowProps = {
  title: 'Dependabot alerts: Email digest',
  subtitle: 'Email a regular summary of Dependabot alerts for up to 10 of your repositories.',
  sx: {pt: 0},
}

const deployKeyAlertRow: RowProps = {
  title: "'Deploy key' alert email",
  subtitle:
    'When you are given admin permissions to an organization, automatically receive notifications when a new deploy key is added.',
  separator: true,
}

const inProductMessagesRow: RowProps = {
  title: 'In-product messages',
  subtitle:
    'Get tips, solutions and exclusive offers from GitHub about products, services and events we think you might find interesting.',
  separator: false,
}

function ActionsSelect({
  selected,
  saveData,
  ...actionProps
}: {
  selected: {[key: string]: boolean}
  saveData: (section: Sections, formData: FormData) => void
} & ActionProps) {
  const [selectedOptions, selectedVariants] = getSelectedOptionsAndVariants(
    selected,
    actionsDropdownOptions,
    actionsDropdownVariants,
  )
  const [continuousIntegrationSelectedOptions, setContinuousIntegrationSelectedOptions] = useState<string[]>(
    selectedOptions || [],
  )
  const [continuousIntegrationSelectedVariants, setContinuousIntegrationSelectedVariants] = useState<string[]>(
    selectedVariants || [],
  )

  const onSaveCallback = (onSaveSelectedOptions: string[], onSaveSelectedVariants: string[]) => {
    const newSelectedVariants = onSaveSelectedOptions.length > 0 ? onSaveSelectedVariants : []
    const formData = new FormData()
    formData.set('continuous_integration_web', onSaveSelectedOptions.includes('continuousIntegrationWeb') ? '1' : '0')
    formData.set(
      'continuous_integration_email',
      onSaveSelectedOptions.includes('continuousIntegrationEmail') ? '1' : '0',
    )
    formData.set(
      'continuous_integration_failures_only',
      newSelectedVariants.includes('continuousIntegrationFailuresOnly') ? '1' : '0',
    )
    saveData(Sections.System, formData)

    setContinuousIntegrationSelectedOptions(onSaveSelectedOptions)
    setContinuousIntegrationSelectedVariants(newSelectedVariants)
  }
  return (
    <MultipleSelect
      title="Select notification channels"
      menuButtonPrefix={defaultPrefix}
      defaultMenuButtonOption={defaultOption}
      menuButtonOptions={actionsDisplayOptions}
      menuButtonVariants={actionsDisplayVariants}
      listOptions={actionsDropdownOptions}
      listVariants={actionsDropdownVariants}
      selectedListOptions={continuousIntegrationSelectedOptions}
      selectedListVariants={continuousIntegrationSelectedVariants}
      onSaveCallback={onSaveCallback}
      {...actionProps}
    />
  )
}

function VulnerabilitySelect({
  selected,
  saveData,
  ...actionProps
}: {
  selected: {[key: string]: boolean}
  saveData: (section: Sections, formData: FormData) => void
} & ActionProps) {
  const [selectedOptions] = getSelectedOptionsAndVariants(selected, vulnerabilityDropdownOptions, {})
  const [vulnerabilitySelectedOptions, setVulnerabilitySelectedOptions] = useState<string[]>(selectedOptions || [])

  const onSaveCallback = (onSaveSelectedOptions: string[]) => {
    const formData = new FormData()
    formData.set('vulnerability_web', onSaveSelectedOptions.includes('vulnerabilityWeb') ? '1' : '0')
    formData.set('vulnerability_cli', onSaveSelectedOptions.includes('vulnerabilityCli') ? '1' : '0')
    formData.set('vulnerability_email', onSaveSelectedOptions.includes('vulnerabilityEmail') ? '1' : '0')
    saveData(Sections.System, formData)

    setVulnerabilitySelectedOptions(onSaveSelectedOptions)
  }

  return (
    <MultipleSelect
      title="Select notification channels"
      menuButtonPrefix={defaultPrefix}
      defaultMenuButtonOption={defaultOption}
      menuButtonOptions={vulnerabilityDisplayOptions}
      listOptions={vulnerabilityDropdownOptions}
      selectedListOptions={vulnerabilitySelectedOptions}
      onSaveCallback={onSaveCallback}
      {...actionProps}
    />
  )
}

function DeployKeyToggle({
  checked,
  saveData,
  'aria-labelledby': ariaLabelledBy,
  ...actionProps
}: {checked: boolean; saveData: (section: Sections, formData: FormData) => void} & ActionProps) {
  const [deployKeyAlertChecked, setDeployKeyAlertChecked] = useState<boolean>(checked || false)
  const saveDeployKeyAlert = (value: boolean) => {
    setDeployKeyAlertChecked(value)
    const formData = new FormData()
    formData.append(`org_deploy_key_settings[email]`, value ? '1' : '0')
    saveData(Sections.System, formData)
  }

  return (
    <ToggleSwitch
      size="small"
      statusLabelPosition="end"
      sx={{mr: 'auto'}}
      checked={deployKeyAlertChecked}
      onClick={() => saveDeployKeyAlert(!deployKeyAlertChecked)}
      aria-labelledby={ariaLabelledBy || ''}
      {...actionProps}
    />
  )
}

function InProductMessagesToggle({
  checked,
  saveData,
  'aria-labelledby': ariaLabelledBy,
  ...actionProps
}: {checked: boolean; saveData: (section: Sections, formData: FormData) => void} & ActionProps) {
  const [inProductMessagesChecked, setInProductMessagesChecked] = useState<boolean>(checked)
  const saveInProductMessages = (value: boolean) => {
    setInProductMessagesChecked(value)
    const formData = new FormData()
    formData.append('subscribe_to_in_product_messages', value ? '1' : '0')
    saveData(Sections.System, formData)
  }

  return (
    <ToggleSwitch
      size="small"
      statusLabelPosition="end"
      sx={{mr: 'auto'}}
      checked={inProductMessagesChecked}
      onClick={() => saveInProductMessages(!inProductMessagesChecked)}
      aria-labelledby={ariaLabelledBy || ''}
      {...actionProps}
    />
  )
}

interface Props {
  sx?: BetterSystemStyleObject
  continuousIntegration: {[key: string]: boolean}
  vulnerability: {[key: string]: boolean}
  vulnerabilitySubscription: string
  deployKeyAlert: string[]
  actionsUrl: string
  dependabotHelpUrl: string
  saveData: (section: Sections, formData: FormData) => void
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  renderState: (section: Sections) => React.ComponentElement<any, any>
  inProductMessages: boolean
}

function SystemSettings(props: Props) {
  const actionsDesciption = (
    <>
      Notifications for workflow runs on repositories set up with&nbsp;
      <Link inline href={props.actionsUrl}>
        GitHub Actions
      </Link>
      .
    </>
  )
  const dependabotDesciption = (
    <>
      When you&apos;re given access to&nbsp;
      <Link inline href={props.dependabotHelpUrl}>
        Dependabot alerts
      </Link>
      &nbsp;automatically receive notifications when a new vulnerability is found in one of your dependencies.
    </>
  )
  const saveEmailWeeklyDigest = (data: string) => {
    const formData = new FormData()
    if (data.includes('weekly') || data.includes('daily')) {
      formData.set('vulnerability_digest', '1')
      formData.set('subscription_kind', data.includes('weekly') ? 'weekly' : 'daily')
    } else {
      formData.set('vulnerability_digest', '0')
    }
    props.saveData(Sections.System, formData)
  }

  return (
    <Box sx={props.sx}>
      <Table>
        <Header>
          System
          {props.renderState(Sections.System)}
        </Header>
        <Row
          {...actionsRow}
          renderAction={actionsRowActionProps => (
            <ActionsSelect
              selected={props.continuousIntegration}
              saveData={props.saveData}
              {...actionsRowActionProps}
            />
          )}
          subtitle={actionsDesciption}
        />
        <Row
          {...dependabotAlertsRow}
          renderAction={dependabotAlertsRowActionProps => (
            <VulnerabilitySelect
              selected={props.vulnerability}
              saveData={props.saveData}
              {...dependabotAlertsRowActionProps}
            />
          )}
          subtitle={dependabotDesciption}
        />
        <Row
          {...emailWeeklyDigestRow}
          renderAction={emailWeeklyDigestRowActionProps => (
            <SingleSelect
              options={Object.values(digestOptions)}
              defaultOption={digestOptions[(props.vulnerabilitySubscription as keyof typeof digestOptions) || 'none']}
              onChange={saveEmailWeeklyDigest}
              {...emailWeeklyDigestRowActionProps}
            />
          )}
        />
        <Row
          {...deployKeyAlertRow}
          renderAction={deployKeyAlertRowActionProps => (
            <DeployKeyToggle
              checked={props.deployKeyAlert.includes('email')}
              saveData={props.saveData}
              {...deployKeyAlertRowActionProps}
            />
          )}
        />
        <Row
          {...inProductMessagesRow}
          renderAction={inProductMessagesRowActionProps => (
            <InProductMessagesToggle
              checked={props.inProductMessages ?? true}
              saveData={props.saveData}
              {...inProductMessagesRowActionProps}
            />
          )}
        />
      </Table>
    </Box>
  )
}

export default SystemSettings

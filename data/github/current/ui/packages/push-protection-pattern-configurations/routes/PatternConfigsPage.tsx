import {useId, useState} from 'react'
import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {patternConfigsPageRoute} from './pattern-configs-page-route'
import {useMutation} from '@github-ui/react-query'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {CheckIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Label, Link} from '@primer/react'
import {DataTable, Table, type Column} from '@primer/react/experimental'
// eslint-disable-next-line no-restricted-imports
import {BoolSetting} from '@github-ui/secret-scanning/types/settings'
// eslint-disable-next-line no-restricted-imports
import {Button, DismissibleBanner} from '@github-ui/secret-scanning/components'
// eslint-disable-next-line no-restricted-imports
import {toPercentString} from '@github-ui/secret-scanning/utils'
import type {PatternOverride, PatternSetting} from '../types'

export function PatternConfigsPage() {
  const payload = useRouteQuery(patternConfigsPageRoute, 'mainQuery').data
  const patternConfig = payload.pattern_config
  const [patternOverrides, setPatternConfigs] = useState(patternConfig.provider_pattern_overrides)
  const [rowVersion, setRowVersion] = useState(patternConfig.row_version)

  const [selectedSettings, setSelectedSettings] = useState(() => new Map<string, PatternSetting>())
  const mutation = useMutation({
    mutationFn: async () => {
      const res = await reactFetchJSON(patternConfigsPageRoute.generatePath({org: payload.org.login}), {
        method: 'PATCH',
        body: {
          number: patternConfig.number,
          row_version: rowVersion,
          pattern_settings: Array.from(selectedSettings.values()),
        },
      })
      if (!res.ok) {
        throw new Error('Failed to update pattern settings')
      }
      const data = await res.json()
      setRowVersion(data.row_version)
    },
    onSuccess: () => {
      // Reset state so new changes are the new initial
      setPatternConfigs(prev => {
        return prev.map(row => {
          const newSetting = selectedSettings.get(row.id)
          if (newSetting) {
            return {
              ...row,
              setting: newSetting?.push_protection_setting ?? row.setting,
            }
          }
          return row
        })
      })
      setSelectedSettings(new Map())
    },
  })

  const [pageIndex, setPageIndex] = useState(0)
  const pageSize = 15
  const start = pageIndex * pageSize
  const end = start + pageSize
  const data = patternOverrides.slice(start, end)
  const columns: Array<Column<PatternOverride>> = [
    {
      header: 'Name',
      field: 'display_name',
    },
    {
      header: 'Alert total',
      field: 'alert_total',
      align: 'end',
      renderCell: row => {
        return `${row.alert_total.toLocaleString()} (${toPercentString(row.alert_total, patternConfig.total_alerts)})`
      },
    },
    {
      header: 'False positives',
      field: 'false_positives',
      align: 'end',
      renderCell: row => {
        return `${row.false_positives.toLocaleString()} (${toPercentString(row.false_positives, row.alert_total)})`
      },
    },
    {
      header: 'Bypass rate',
      field: 'bypasses',
      align: 'end',
      renderCell: row => {
        return toPercentString(row.bypasses, row.blocks)
      },
    },
    {
      header: 'GitHub default',
      field: 'default_setting',
      renderCell: row => {
        return <span data-testid="default-setting">{boolSettingToString(row.default_setting, 'Unknown')}</span>
      },
    },
  ]
  if (payload.has_parent) {
    columns.push({
      header: 'Inherited state',
      field: 'inherited_setting',
      renderCell: row => {
        return <span data-testid="inherited-setting">{boolSettingToString(row.inherited_setting, 'Unknown')}</span>
      },
    })
  }
  columns.push({
    header: 'Push protection',
    field: 'setting',
    renderCell: row => {
      const currentSetting = selectedSettings.get(row.id)?.push_protection_setting
      return (
        <SettingActionMenu
          row={row}
          // currentSetting is prop passed to useState, so key prop needed to force re-render
          key={currentSetting}
          currentSetting={currentSetting}
          onSelect={result => {
            if (result.isResetToInitial) {
              setSelectedSettings(prev => {
                const newMap = new Map(prev)
                newMap.delete(result.setting.token_type)
                return newMap
              })
            } else {
              setSelectedSettings(prev => new Map(prev.set(result.setting.token_type, result.setting)))
            }
          }}
        />
      )
    },
  })

  const headingId = useId()
  const subHeadingId = useId()
  return (
    <>
      <div className="mb-2">
        <Link href={payload.security_settings_path}>Global settings</Link>
        <span> / Pattern configurations</span>
      </div>
      <h2 data-hpc className="h3" id={headingId}>
        Pattern configuration
      </h2>
      <p className="mb-2" id={subHeadingId}>
        Configure push protection enablement by pattern. Passwords detected with AI are not supported.
      </p>
      <hr className="mt-0 mb-3" />

      {mutation.isSuccess && (
        <DismissibleBanner className="mb-3" variant="success" icon={<CheckIcon />} title="Success" hideTitle>
          Your changes have been applied.
        </DismissibleBanner>
      )}
      {mutation.isError && (
        <DismissibleBanner className="mb-3" variant="critical" title="Error" hideTitle>
          Failed to update pattern settings. Please try again later.
        </DismissibleBanner>
      )}

      <Table.Container>
        <DataTable aria-labelledby={headingId} aria-describedby={subHeadingId} data={data} columns={columns} />
        <Table.Pagination
          aria-label="Pagination for pattern configs"
          totalCount={patternOverrides.length}
          pageSize={pageSize}
          onChange={({pageIndex: newPageIndex}) => setPageIndex(newPageIndex)}
        />
      </Table.Container>
      <div className="d-flex gap-2 mt-3">
        <Button
          variant="primary"
          inactive={selectedSettings.size === 0}
          loading={mutation.isPending}
          onClick={() => mutation.mutate()}
        >
          Apply changes
        </Button>
        <Button
          inactive={selectedSettings.size === 0 || mutation.isPending}
          onClick={() => {
            setSelectedSettings(new Map())
          }}
        >
          Cancel
        </Button>
      </div>
    </>
  )
}

function SettingActionMenu({
  row,
  currentSetting,
  onSelect,
}: {
  row: PatternOverride
  currentSetting?: BoolSetting
  onSelect: (setting: {setting: PatternSetting; isResetToInitial: boolean}) => void
}) {
  const [setting, setSetting] = useState(currentSetting ?? row.setting)

  const initialSetting = row.setting
  function handleSettingChange(newSetting: BoolSetting) {
    setSetting(newSetting)
    onSelect({
      setting: {
        token_type: row.id,
        push_protection_setting: newSetting,
      },
      isResetToInitial: newSetting === initialSetting,
    })
  }

  return (
    <ActionMenu>
      <ActionMenu.Button style={{minWidth: '104px'}} alignContent="start">
        {boolSettingToString(setting, 'Default')}
      </ActionMenu.Button>
      <ActionMenu.Overlay width="small">
        <ActionList selectionVariant="single">
          <ActionList.Item
            selected={setting === BoolSetting.Enabled}
            aria-checked={setting === BoolSetting.Enabled}
            onSelect={() => handleSettingChange(BoolSetting.Enabled)}
          >
            Enabled
          </ActionList.Item>
          <ActionList.Item
            selected={setting === BoolSetting.Disabled}
            aria-checked={setting === BoolSetting.Disabled}
            onSelect={() => handleSettingChange(BoolSetting.Disabled)}
          >
            Disabled
          </ActionList.Item>
          {/* TODO: Handle swapping between "default" and "inherited" once we add to enterprise level */}
          <ActionList.Item
            selected={setting === BoolSetting.NotSet}
            aria-checked={setting === BoolSetting.NotSet}
            onSelect={() => handleSettingChange(BoolSetting.NotSet)}
          >
            <span className="text-normal">GitHub default</span>
            <ActionList.TrailingVisual>
              <Label>{boolSettingToString(row.default_setting, 'Unknown')}</Label>
            </ActionList.TrailingVisual>
            <ActionList.Description variant="block">
              This state may change based on GitHub&apos;s recommendations
            </ActionList.Description>
          </ActionList.Item>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}

function boolSettingToString(setting: BoolSetting, notSetText: string): string {
  switch (setting) {
    case BoolSetting.Enabled:
      return 'Enabled'
    case BoolSetting.Disabled:
      return 'Disabled'
    case BoolSetting.NotSet:
      return notSetText
    default:
      return setting satisfies never
  }
}

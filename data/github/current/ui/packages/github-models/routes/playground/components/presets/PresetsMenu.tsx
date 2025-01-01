import {useMemo, useRef, useState} from 'react'
import {ActionList, ActionMenu, Label, Truncate} from '@primer/react'
import {PencilIcon, PlusIcon, ShareIcon, TrashIcon} from '@primer/octicons-react'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {modelPlaygroundPath} from '@github-ui/paths'
import {PresetDialog} from './PresetDialog'
import {DeletePresetDialog} from './DeletePresetDialog'
import {SharePresetDialog} from './SharePresetDialog'
import type {Preset, PresetsPayload} from '../../../../types'
import {Panel} from '../../../../utils/playground-manager'
import {usePlaygroundManager} from '../../../../contexts/PlaygroundManagerContext'
import {useSearchParams} from '@github-ui/use-navigate'
import {getModelState} from '../../../../utils/model-state'
import {useClickAnalytics} from '@github-ui/use-analytics'
import {usePlaygroundState} from '../../../../contexts/PlaygroundStateContext'
import {getTextFromMessage, isValidString} from '../../../../utils/presets'
import styles from './PresetsMenu.module.css'
import {useQuery} from '@github-ui/react-query'

export const getDefaultPreset = () => ({
  name: 'Default',
  parameters: {
    system_prompt: '',
  },
  private: true,
  urlIdentifier: '',
})

export function PresetsMenu() {
  const {models} = usePlaygroundState()
  const manager = usePlaygroundManager()
  const [searchParams, setSearchParams] = useSearchParams()
  const {sendClickAnalyticsEvent} = useClickAnalytics()
  const defaultPreset = useMemo(() => getDefaultPreset(), [])

  const [action, setAction] = useState<'create' | 'update'>('create')
  const [showDeletePresetDialog, setShowDeletePresetDialog] = useState(false)
  const [showPresetDialog, setShowPresetDialog] = useState(false)
  const [showSharePresetDialog, setShowSharePresetDialog] = useState(false)

  const anchorRef = useRef<HTMLElement>(null)

  const {data: presetsData, refetch} = useQuery<PresetsPayload>({
    queryKey: ['github-models', 'presets'],
    async queryFn() {
      const res = await verifiedFetchJSON('/marketplace/models/presets')
      if (!res.ok) throw new Error(await res.text())
      return await res.json()
    },
  })

  const presets = useMemo<Preset[]>(() => {
    if (presetsData?.presets != null) {
      return [defaultPreset, ...presetsData?.presets]
    }
    return [defaultPreset]
  }, [defaultPreset, presetsData])

  const limitPerUser = useMemo(() => {
    return presetsData?.limit_per_user ?? 0
  }, [presetsData])

  // Presets are only available in single model mode
  if (models.length > 1) return null
  const mainModel = models[Panel.Main]
  if (!mainModel) return null

  const {catalogData, modelInputSchema, gettingStarted, systemPrompt = '', chatInput = '', messages = []} = mainModel

  const presetFromURL: string = searchParams.get('preset')?.toLowerCase() ?? ''
  const selectedPreset =
    presets.find(({urlIdentifier}) => urlIdentifier.toLowerCase() === presetFromURL) ?? defaultPreset
  const doClickEvent = (type: 'create' | 'edit' | 'delete' | 'share' | 'open') => {
    sendClickAnalyticsEvent({
      category: 'github_models_playground',
      action: `click_to_${type}_preset`,
      label: `ref_cta:${type}_preset;ref_loc:presets_menu`,
    })
  }

  const onSuccess = async (preset?: string) => {
    refetch()
    setSearchParams(preset ? {preset} : {})
  }

  const selectAndApplyPreset = (preset: Preset) => {
    const modelDetails = {
      catalogData,
      modelInputSchema,
      gettingStarted,
    }

    if (preset.urlIdentifier === '') {
      // This is the default preset
      setSearchParams({})
      manager.setModelState(Panel.Main, getModelState(modelDetails))
    } else {
      setSearchParams({preset: preset.urlIdentifier})
      manager.setModelState(Panel.Main, getModelState(modelDetails, preset))
    }
  }

  const defaultPresetSelected = selectedPreset.name === 'Default'
  // A preset requires a system prompt, chat input, or user message to be saved
  const hasContent =
    isValidString(systemPrompt) || getTextFromMessage(chatInput) || getTextFromMessage(messages[0]?.message)

  const presetActions = [
    {
      name: 'Save prompt as new preset',
      icon: <PlusIcon />,
      onSelect: () => {
        setShowPresetDialog(true)
        setAction('create')
        doClickEvent('create')
      },
      // The default preset isn't counted in the preset limit
      disabled: presets.length > limitPerUser,
      show: hasContent,
    },
    {
      name: 'Update',
      icon: <PencilIcon />,
      onSelect: () => {
        setShowPresetDialog(true)
        setAction('update')
        doClickEvent('edit')
      },
      disabled: !hasContent,
      show: !defaultPresetSelected && hasContent,
    },
    {
      name: 'Delete',
      icon: <TrashIcon />,
      onSelect: () => {
        setShowDeletePresetDialog(true)
        doClickEvent('delete')
      },
      show: !defaultPresetSelected,
    },
    {
      name: 'Share',
      icon: <ShareIcon />,
      onSelect: () => {
        setShowSharePresetDialog(true)
        doClickEvent('share')
      },
      show: !selectedPreset.private,
    },
  ].filter(({show}) => show)

  // Return focus to the anchor when dialogs closes
  function returnFocusToPresetButton() {
    // Ensure focus restoration happens after React re-renders
    globalThis.requestAnimationFrame(() => {
      anchorRef.current?.focus()
    })
  }

  return (
    <>
      <ActionMenu anchorRef={anchorRef}>
        <ActionMenu.Button>
          <span className="fgColor-muted">Preset:</span>{' '}
          <Truncate inline title={selectedPreset.name} maxWidth="20ch">
            {selectedPreset.name}
          </Truncate>
        </ActionMenu.Button>
        <ActionMenu.Overlay width="medium">
          <ActionList className={styles.presetActionList}>
            {presetActions.length ? (
              <ActionList.Group>
                {presetActions.map(({name, icon, onSelect, disabled}) => (
                  <ActionList.Item key={name} onSelect={onSelect} disabled={disabled}>
                    <ActionList.LeadingVisual>{icon}</ActionList.LeadingVisual>
                    {name}
                  </ActionList.Item>
                ))}
                <ActionList.Divider className="mb-0" />
              </ActionList.Group>
            ) : null}
            <ActionList.Group selectionVariant="single">
              {presets.map(preset => (
                <ActionList.Item
                  key={preset.name}
                  selected={preset.urlIdentifier === selectedPreset.urlIdentifier}
                  onSelect={() => {
                    selectAndApplyPreset(preset)
                    doClickEvent('open')
                  }}
                >
                  <div className="d-flex flex-justify-between flex-items-center">
                    <div>{preset.name}</div>
                    {!preset.private && <Label>Shared</Label>}
                  </div>
                  {preset.parameters.system_prompt ? (
                    <ActionList.Description variant="block">
                      <span className="line-clamp-2">{preset.parameters.system_prompt}</span>
                    </ActionList.Description>
                  ) : null}
                </ActionList.Item>
              ))}
            </ActionList.Group>
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      {showPresetDialog && (
        <PresetDialog
          onClose={() => {
            setShowPresetDialog(false)
            returnFocusToPresetButton()
          }}
          onSuccess={onSuccess}
          selectedPreset={selectedPreset}
          action={action}
        />
      )}
      {showDeletePresetDialog && (
        <DeletePresetDialog
          onClose={() => {
            setShowDeletePresetDialog(false)
            returnFocusToPresetButton()
          }}
          onSuccess={onSuccess}
          selectedPreset={selectedPreset}
        />
      )}
      {showSharePresetDialog && (
        <SharePresetDialog
          onClose={() => {
            setShowSharePresetDialog(false)
            returnFocusToPresetButton()
          }}
          playgroundUrl={modelPlaygroundPath(catalogData)}
          urlIdentifier={selectedPreset.urlIdentifier}
        />
      )}
    </>
  )
}

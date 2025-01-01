import {useEffect, useState} from 'react'
import {ActionList, ActionMenu, Label, Truncate} from '@primer/react'
import {PencilIcon, PlusIcon, ShareIcon, TrashIcon} from '@primer/octicons-react'
import {useSafeAsyncCallback} from '@github-ui/use-safe-async-callback'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {PresetDialog} from './PresetDialog'
import {DeletePresetDialog} from './DeletePresetDialog'
import {SharePresetDialog} from './SharePresetDialog'
import type {ModelDetails, Preset, PresetsPayload} from '../../../../types'
import {Panel, usePlaygroundManager} from '../../../../utils/playground-manager'
import {ModelUrlHelper} from '../../../../utils/model-url-helper'
import {createPreset, deletePreset, getModelStateFromPreset, updatePreset} from '../../../../utils/presets'
import {useSearchParams} from '@github-ui/use-navigate'
import {getModelStateDefaults, getParameterSchema} from '../../../../utils/model-state'

import styles from './PresetsMenu.module.css'

const getDefaultPreset = (modelDetails: ModelDetails) => ({
  name: 'Default',
  conversationHistory: [],
  description: '',
  parameters: getParameterSchema(modelDetails.modelInputSchema?.parameters),
  private: true,
  urlIdentifier: '',
})

export function PresetsMenu({modelDetails}: {modelDetails: ModelDetails}) {
  const manager = usePlaygroundManager()
  const defaultPreset = getDefaultPreset(modelDetails)

  const [presets, setPresets] = useState<Preset[]>([defaultPreset])
  const [limitPerUser, setLimitPerUser] = useState(0)

  const [searchParams, setSearchParams] = useSearchParams()
  const presetFromURL: string = searchParams.get('preset')?.toLowerCase() ?? ''
  const selectedPreset = presets.find(({urlIdentifier}) => urlIdentifier.toLowerCase() === presetFromURL) ?? null

  const [showDeletePresetDialog, setShowDeletePresetDialog] = useState(false)
  const [showPresetDialog, setShowPresetDialog] = useState(false)
  const [showSharePresetDialog, setShowSharePresetDialog] = useState(false)
  const [showDeletePresetDialogErrors, setShowDeletePresetDialogErrors] = useState<string>('')
  const [showPresetDialogErrors, setShowPresetDialogErrors] = useState<object | null>(null)
  const [action, setAction] = useState<'create' | 'update'>('create')

  const loadPresets = useSafeAsyncCallback(async () => {
    const res = await verifiedFetchJSON('/marketplace/models/presets')
    if (res?.ok) {
      const presetsResponse: PresetsPayload = await res.json()
      const updatedPresets = [defaultPreset, ...presetsResponse.presets]
      setPresets(updatedPresets)
      setLimitPerUser(presetsResponse.limit_per_user)
    }
  })

  useEffect(() => {
    loadPresets()

    if (!showPresetDialog) {
      setShowPresetDialogErrors(null)
    }

    if (!showDeletePresetDialog) {
      setShowDeletePresetDialogErrors('')
    }
  }, [loadPresets, showPresetDialog, showDeletePresetDialog])

  const onSavePreset = async (presetData: Preset) => {
    try {
      const {urlIdentifier, includeChatHistory, ...savePresetData} = presetData

      // Add logic to check if includeChatHistory is defined and false
      if (includeChatHistory === false) {
        savePresetData.conversationHistory = []
      }

      const isCreating = action === 'create'
      const res = isCreating
        ? await createPreset({preset: savePresetData})
        : await updatePreset({urlIdentifier, preset: savePresetData})

      if (res.ok) {
        setShowPresetDialogErrors({})
        const newPreset = (await res.json()) as Preset

        const presetsList = isCreating
          ? presets
          : presets.map(preset => (preset.urlIdentifier === urlIdentifier ? newPreset : preset))
        const updatedPresets = [...presetsList.slice(1), newPreset].sort((a, b) => a.name.localeCompare(b.name))
        setPresets([defaultPreset, ...updatedPresets])
        setSearchParams({
          preset: newPreset.urlIdentifier,
        })
      } else {
        const body = await res.json()
        setShowPresetDialogErrors(body.error)
        return
      }
    } catch {
      setShowPresetDialogErrors({error: [`Failed to ${action} preset: ${presetData.name}`]})
      return
    }
    setShowPresetDialog(false)
  }

  const onDeletePreset = async (presetData: Preset) => {
    try {
      const {urlIdentifier} = presetData
      const res = await deletePreset({urlIdentifier})

      if (res.ok) {
        const updatedPresets = presets.filter(preset => preset.urlIdentifier !== urlIdentifier)

        setPresets(updatedPresets)
        setSearchParams({})
      }
    } catch {
      setShowDeletePresetDialogErrors(`Failed to delete ${presetData.name} preset. Try again later.`)
      return
    }
    setShowDeletePresetDialog(false)
  }

  const defaultPresetSelected = selectedPreset?.name === 'Default'
  // The default preset isn't counted in the preset limit
  const limitPerUserReached = presets.length > limitPerUser
  const presetIsEditable = !defaultPresetSelected
  const showSharePreset = !defaultPresetSelected && !selectedPreset?.private

  const selectAndApplyPreset = (preset: Preset) => {
    if (preset.urlIdentifier === '') {
      // This is the default preset
      setSearchParams({})
      manager.setModelState(Panel.Main, getModelStateDefaults(modelDetails))
    } else {
      setSearchParams({preset: preset.urlIdentifier})
      manager.setModelState(Panel.Main, getModelStateFromPreset(preset, modelDetails))
    }
  }

  return (
    <>
      <ActionMenu>
        <ActionMenu.Button>
          <span className={styles.menuButtonPrefix}>Preset:</span>{' '}
          <Truncate inline className={styles.presetName} title={`${selectedPreset?.name ?? ''}`}>
            {selectedPreset?.name ?? ''}
          </Truncate>
        </ActionMenu.Button>
        <ActionMenu.Overlay width="medium">
          <ActionList className={styles.menuList}>
            <ActionList.Group>
              <ActionList.Item
                onSelect={() => {
                  setShowPresetDialog(true)
                  setShowPresetDialogErrors(null)
                  setAction('create')
                }}
                disabled={limitPerUserReached}
              >
                <ActionList.LeadingVisual>
                  <PlusIcon />
                </ActionList.LeadingVisual>
                Create new preset
              </ActionList.Item>
              {presetIsEditable ? (
                <ActionList.Item
                  onSelect={() => {
                    setShowPresetDialog(true)
                    setAction('update')
                  }}
                >
                  <ActionList.LeadingVisual>
                    <PencilIcon />
                  </ActionList.LeadingVisual>
                  Edit preset
                </ActionList.Item>
              ) : null}
              {presetIsEditable ? (
                <ActionList.Item
                  onSelect={() => {
                    setShowDeletePresetDialog(true)
                  }}
                >
                  <ActionList.LeadingVisual>
                    <TrashIcon />
                  </ActionList.LeadingVisual>
                  Delete preset
                </ActionList.Item>
              ) : null}
              {showSharePreset ? (
                <ActionList.Item
                  onSelect={() => {
                    setShowSharePresetDialog(true)
                  }}
                >
                  <ActionList.LeadingVisual>
                    <ShareIcon />
                  </ActionList.LeadingVisual>
                  Share preset
                </ActionList.Item>
              ) : null}
            </ActionList.Group>
            <ActionList.Group selectionVariant="single" sx={{maxHeight: '50vh', overflowY: 'scroll', pb: '2'}}>
              <ActionList.Divider sx={{mt: '0'}} />
              {presets.map(preset => (
                <ActionList.Item
                  key={preset.name}
                  selected={preset.urlIdentifier === selectedPreset?.urlIdentifier}
                  onSelect={() => selectAndApplyPreset(preset)}
                >
                  <div className={styles.presetsListItem}>
                    <div className={styles.presetName}>{preset.name}</div>
                    {!preset.private && <Label>Shared</Label>}
                  </div>
                  <ActionList.Description variant="block">
                    <span className="line-clamp-2">{preset.description}</span>
                  </ActionList.Description>
                </ActionList.Item>
              ))}
            </ActionList.Group>
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      {showPresetDialog && (
        <PresetDialog
          onClose={() => setShowPresetDialog(false)}
          onSubmit={onSavePreset}
          selectedPreset={selectedPreset}
          action={action}
          errors={showPresetDialogErrors}
        />
      )}
      {showDeletePresetDialog && selectedPreset && (
        <DeletePresetDialog
          onClose={() => setShowDeletePresetDialog(false)}
          onSubmit={onDeletePreset}
          selectedPreset={selectedPreset}
          errors={showDeletePresetDialogErrors}
        />
      )}
      {showSharePresetDialog && (
        <SharePresetDialog
          onClose={() => setShowSharePresetDialog(false)}
          playgroundUrl={ModelUrlHelper.playgroundUrl(modelDetails.catalogData)}
          urlIdentifier={selectedPreset?.urlIdentifier}
        />
      )}
    </>
  )
}

import {useCallback, useState} from 'react'
import {Box, Button, IconButton} from '@primer/react'
import {CodeIcon, XIcon} from '@primer/octicons-react'
import type {GettingStarted, ModelInputSchema, SidebarSelectionOptions} from '../../../../types'
import type {Model} from '@github-ui/marketplace-common'
import {GettingStartedButtonClicked, templateRepositoryNwo} from '../../../../utils/playground-types'
import {ModelUrlHelper} from '../../../../utils/model-url-helper'
import ModelSwitcher from '../ModelSwitcher'
import GettingStartedDialog from './GettingStartedDialog'
import {PresetsMenu} from '../presets/PresetsMenu'
import {sendEvent} from '@github-ui/hydro-analytics'
import {Panel, usePlaygroundManager} from '../../../../utils/playground-manager'
import {usePlaygroundState} from '../../../../contexts/PlaygroundStateContext'
import {useNavigate, useSearchParams} from 'react-router-dom'
import {GiveFeedback} from './GiveFeedback'

export function PlaygroundHeader({
  model,
  modelInputSchema,
  canUseO1Models,
  position,
  gettingStarted,
  handleSetSidebarTab,
}: {
  model: Model
  modelInputSchema: ModelInputSchema
  canUseO1Models: boolean
  position: number
  gettingStarted: GettingStarted
  handleSetSidebarTab: (newTab: SidebarSelectionOptions) => void
}) {
  const manager = usePlaygroundManager()
  const openInCodespacesUrl = `/codespaces/new?template_repository=${templateRepositoryNwo}`
  const [isGettingStartedDialogOpen, setGettingStartedDialogOpen] = useState(false)

  const {models = [], syncInputs = false} = usePlaygroundState()
  const onComparisonMode = models.length > 1
  const navigate = useNavigate()
  const [searchParams, setSearchParams] = useSearchParams()

  const comparisonStyle = {
    p: 2,
    pb: 2,
    borderColor: 'border.default',
    borderWidth: 1,
    borderStyle: 'solid',
    borderTopRightRadius: 2,
    borderTopLeftRadius: 2,
  }

  const individualStyle = {
    p: 0,
    pb: 3,
    borderColor: null,
    borderWidth: 0,
    borderStyle: null,
    borderTopRightRadius: 0,
    borderTopLeftRadius: 0,
  }

  const onCloseModel = () => {
    manager.setSyncInputs(false)
    if (position !== Panel.Main) {
      manager.controller?.abort()
    }
    manager.removeModel(position)
    searchParams.delete('compare_to')
    const newPosition = position === Panel.Main ? Panel.Side : Panel.Main

    if (position === Panel.Main) {
      // If we're removing the main model, we need to navigate to the new main model
      navigate({
        pathname: ModelUrlHelper.playgroundUrl(models[newPosition]?.catalogData || model),
        search: searchParams.toString(),
      })
    } else {
      // If we're removing the side model, we just remove the compare_to
      setSearchParams(searchParams)
    }
  }

  const onModelSelect = useCallback(
    async (m: Model) => {
      if (position === Panel.Side && models[Panel.Side]) {
        const response = await manager.getSideModel(m.name, models[Panel.Side], syncInputs)
        if (!response.success) return
        setSearchParams(p => {
          p.set('compare_to', m.name)
          return p
        })
      } else {
        navigate({
          pathname: ModelUrlHelper.playgroundUrl(m),
        })
      }
    },
    // Apparently "models[Panel.Side]" is not a "simple enough expression"
    // eslint-disable-next-line react-compiler/react-compiler
    [models[Panel.Side], position, syncInputs, manager],
  )

  return (
    <Box
      sx={{
        ...(onComparisonMode ? comparisonStyle : individualStyle),
        display: 'flex',
        gap: 3,
        flexDirection: 'column',
        borderBottomWidth: 0,
      }}
    >
      <div>
        <Box
          sx={{
            display: 'flex',
            justifyContent: 'center',
            flexDirection: 'row',
            alignItems: 'center',
            gap: 3,
          }}
        >
          <Box
            sx={{
              flexGrow: 1,
              display: 'flex',
              minWidth: [0, 0, '320px'], // This is to avoid having different sizes for each playground on comparison view. As of shipping, the longest model name is about 320px.
              alignItems: 'center',
              width: 'auto',
            }}
          >
            <ModelSwitcher
              model={model}
              canUseO1Models={canUseO1Models}
              onSelect={onModelSelect}
              onComparisonMode={onComparisonMode}
              handleSetSidebarTab={handleSetSidebarTab}
            />
          </Box>
          <Box
            sx={{
              display: 'flex',
              gap: 2,
              width: 'auto',
              justifyContent: 'flex-end',
              flexGrow: 1,
              flexShrink: 0,
              flexDirection: 'row',
            }}
          >
            <Box sx={{display: ['none', 'none', 'flex']}}>{!onComparisonMode && <GiveFeedback />}</Box>

            {!onComparisonMode && (
              <Box sx={{display: ['none', 'none', 'flex']}}>
                <PresetsMenu
                  modelDetails={{
                    catalogData: model,
                    modelInputSchema,
                    gettingStarted,
                  }}
                />
              </Box>
            )}

            <>
              <IconButton
                sx={{display: ['flex', 'none', 'none']}}
                icon={CodeIcon}
                variant="primary"
                aria-label="Get API key"
                onClick={() => {
                  setGettingStartedDialogOpen(true)
                  sendEvent(GettingStartedButtonClicked, {
                    registry: model.registry,
                    model: model.name,
                    publisher: model.publisher,
                  })
                }}
              />
              <Button
                sx={{display: ['none', 'flex', 'flex']}}
                leadingVisual={CodeIcon}
                variant="primary"
                onClick={() => {
                  setGettingStartedDialogOpen(true)
                  sendEvent(GettingStartedButtonClicked, {
                    registry: model.registry,
                    model: model.name,
                    publisher: model.publisher,
                  })
                }}
              >
                Get API key
              </Button>
              {onComparisonMode && <IconButton icon={XIcon} aria-label="Close model" onClick={onCloseModel} />}
            </>
            {isGettingStartedDialogOpen && (
              <GettingStartedDialog
                openInCodespaceUrl={openInCodespacesUrl}
                onClose={() => setGettingStartedDialogOpen(false)}
                showCodespacesSuggestion
                gettingStarted={gettingStarted}
                modelName={model.name}
              />
            )}
          </Box>
        </Box>
      </div>
    </Box>
  )
}

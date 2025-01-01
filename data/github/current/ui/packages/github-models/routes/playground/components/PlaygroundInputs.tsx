import {Box, SegmentedControl, IconButton, useResponsiveValue} from '@primer/react'
import {SidebarCollapseIcon, TrashIcon} from '@primer/octicons-react'
import {Tooltip} from '@primer/react/next'
import {usePlaygroundManager} from '../../../utils/playground-manager'
import {useSearchParams} from '@github-ui/use-navigate'
import type {ModelState} from '../../../types'
import {SidebarSelectionOptions} from '../../../types'
import {MobileInputs} from './MobileInputs'
import {SidebarContent} from './SidebarContent'

interface PlaygroundInputsProps {
  model: ModelState
  position: number
  sidebarTab: SidebarSelectionOptions
  showSidebar: boolean
  showSidebarOnMobile: boolean
  handleSetSidebarTab: (value: SidebarSelectionOptions) => void
  handleShowSidebar: (value: boolean) => void
  handleShowSidebarOnMobile: (value: boolean) => void
}

export function PlaygroundInputs({
  model,
  position,
  sidebarTab,
  showSidebar,
  showSidebarOnMobile,
  handleSetSidebarTab,
  handleShowSidebar,
  handleShowSidebarOnMobile,
}: PlaygroundInputsProps) {
  const isMobile = useResponsiveValue({narrow: true}, false)
  const manager = usePlaygroundManager()
  const [_, setSearchParams] = useSearchParams()

  const resetLabel = 'Reset to default inputs'

  const doReset = () => {
    const modelDetails = {
      catalogData: model.catalogData,
      modelInputSchema: model.modelInputSchema,
      gettingStarted: model.gettingStarted,
    }
    setSearchParams({})
    manager.resetParamsAndSystemPrompt(position, modelDetails)
  }

  if (isMobile && showSidebarOnMobile) {
    return (
      <MobileInputs
        sidebarTab={sidebarTab}
        modelState={model}
        position={position}
        resetLabel={resetLabel}
        handleShowSidebarOnMobile={handleShowSidebarOnMobile}
        doReset={doReset}
      />
    )
  }

  const smallSizeForSegmentControl = {
    height: '28px',
    fontSize: 1,
  }

  return (
    <Box
      sx={{
        height: '100%',
        flexDirection: 'column',
        width: '30%',
        maxWidth: '480px',
        minWidth: '280px',
        overflow: 'auto',
        display: showSidebar ? ['none', 'none', 'flex'] : 'none',
      }}
      className="border-top border-md-top-0 border-md-left"
    >
      <div
        className="d-flex flex-justify-between position-sticky top-0 p-2 border-bottom bgColor-muted flex-items-center"
        style={{zIndex: 1}}
      >
        <div className="flex-1 pr-2">
          <SegmentedControl
            sx={smallSizeForSegmentControl}
            size="small"
            onChange={handleSetSidebarTab}
            fullWidth={{narrow: true, regular: false}}
            aria-label="Mode"
          >
            <SegmentedControl.Button selected={sidebarTab === SidebarSelectionOptions.PARAMETERS}>
              Parameters
            </SegmentedControl.Button>
            <SegmentedControl.Button selected={sidebarTab === SidebarSelectionOptions.DETAILS}>
              Details
            </SegmentedControl.Button>
          </SegmentedControl>
        </div>
        <div>
          {sidebarTab === SidebarSelectionOptions.PARAMETERS && model.parametersHasChanges && (
            <Tooltip text={resetLabel}>
              <IconButton size="small" icon={TrashIcon} as="button" aria-label={resetLabel} onClick={doReset} />
            </Tooltip>
          )}
          <IconButton
            size="small"
            icon={SidebarCollapseIcon}
            aria-label="Hide parameters setting"
            onClick={() => handleShowSidebar(false)}
            className="ml-2"
          />
        </div>
      </div>

      <SidebarContent activeTab={sidebarTab} modelState={model} position={position} />
    </Box>
  )
}

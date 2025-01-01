import {SegmentedControl, IconButton, useResponsiveValue, Stack} from '@primer/react'
import {SidebarExpandIcon, TrashIcon} from '@primer/octicons-react'
import {Tooltip} from '@primer/react/next'
import {usePlaygroundManager} from '../../../contexts/PlaygroundManagerContext'
import {useSearchParams} from '@github-ui/use-navigate'
import type {ModelState} from '../../../types'
import {SidebarSelectionOptions} from '../../../types'
import {MobileInputs} from './ModelParametersSidebar/MobileInputs'
import {SidebarContent} from './ModelParametersSidebar/SidebarContent'
import styles from './PlaygroundInputs.module.css'
import {CreatePromptFileButton} from './CreatePromptFileButton'
import type {Repository} from '@github-ui/paths'

interface PlaygroundInputsProps {
  model: ModelState
  position: number
  sidebarTab: SidebarSelectionOptions
  showSidebar: boolean
  showSidebarOnMobile: boolean
  handleSetSidebarTab: (value: number) => void
  handleShowSidebar: (value: boolean) => void
  handleShowSidebarOnMobile: (value: boolean) => void
  repository?: Repository
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
  repository,
}: PlaygroundInputsProps) {
  const isMobile = useResponsiveValue({narrow: true}, false)
  const manager = usePlaygroundManager()
  const [searchParams, setSearchParams] = useSearchParams()

  const resetLabel = 'Reset to default inputs'

  const doReset = () => {
    const modelDetails = {
      catalogData: model.catalogData,
      modelInputSchema: model.modelInputSchema,
      gettingStarted: model.gettingStarted,
    }

    if (searchParams.get('preset')) setSearchParams()
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
        repository={repository}
      />
    )
  }

  return (
    <div
      className={`${styles.container} ${
        showSidebar ? styles.showSidebar : ''
      } border-top border-md-top-0 border-md-right position-relative`}
    >
      <div
        className="d-flex flex-justify-between position-sticky top-0 p-2 border-bottom bgColor-muted flex-items-center"
        style={{zIndex: 1}}
      >
        <div className="flex-1 pr-2">
          <SegmentedControl
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
            icon={SidebarExpandIcon}
            aria-label="Hide parameters setting"
            onClick={() => handleShowSidebar(false)}
            className="ml-2"
          />
        </div>
      </div>

      <SidebarContent activeTab={sidebarTab} modelState={model} position={position} />

      {repository && sidebarTab === SidebarSelectionOptions.PARAMETERS && (
        <Stack className={styles.buttonWrapper}>
          <CreatePromptFileButton modelState={model} repository={repository} />
        </Stack>
      )}
    </div>
  )
}

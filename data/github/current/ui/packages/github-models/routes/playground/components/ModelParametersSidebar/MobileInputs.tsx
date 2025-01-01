import {IconButton} from '@primer/react'
import {TrashIcon} from '@primer/octicons-react'
import {Tooltip} from '@primer/react/next'
import {Dialog} from '@primer/react/experimental'
import type {ModelState} from '../../../../types'
import {SidebarSelectionOptions} from '../../../../types'
import {SidebarContent} from './SidebarContent'

interface MobileInputsProps {
  sidebarTab: SidebarSelectionOptions
  modelState: ModelState
  position: number
  resetLabel: string
  handleShowSidebarOnMobile: (value: boolean) => void
  doReset: () => void
}

export function MobileInputs({
  sidebarTab,
  modelState,
  position,
  resetLabel,
  handleShowSidebarOnMobile,
  doReset,
}: MobileInputsProps) {
  return (
    <Dialog
      position={{narrow: 'fullscreen', regular: 'center'}}
      renderHeader={({dialogLabelId}) => {
        return (
          <Dialog.Header className="d-flex flex-items-center flex-justify-between">
            <Dialog.Title id={dialogLabelId} className="px-2 flex-direction-column">
              {sidebarTab === SidebarSelectionOptions.DETAILS ? 'Info' : 'Parameters'}
            </Dialog.Title>
            {sidebarTab === SidebarSelectionOptions.PARAMETERS && modelState.parametersHasChanges && (
              <Tooltip text={resetLabel}>
                <IconButton
                  icon={TrashIcon}
                  as="button"
                  variant="invisible"
                  aria-label={resetLabel}
                  onClick={doReset}
                />
              </Tooltip>
            )}
            <Dialog.CloseButton onClose={() => handleShowSidebarOnMobile(false)} />
          </Dialog.Header>
        )
      }}
      onClose={() => handleShowSidebarOnMobile(false)}
    >
      <SidebarContent headingLevel="h2" activeTab={sidebarTab} modelState={modelState} position={position} />
    </Dialog>
  )
}

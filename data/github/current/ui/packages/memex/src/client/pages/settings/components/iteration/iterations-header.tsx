import {testIdProps} from '@github-ui/test-id-props'
import {ArchiveIcon, ClockIcon} from '@primer/octicons-react'
import {type BetterSystemStyleObject, Box, Button} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import type {IterationConfiguration} from '../../../../api/columns/contracts/iteration'
import {BaseIterationRowStyle} from './iteration-row-skeleton'
import styles from './iterations-header.module.css'
import {NewIterationModalButton, type NewIterationModalButtonProps} from './new-iteration-modal-button'
import type {SelectedTab} from './types'

type IterationHeaderProps = {
  selectedTab: SelectedTab
  setSelectedTab: (tab: SelectedTab) => void
  configuration: IterationConfiguration
  addButtonProps: NewIterationModalButtonProps
  disabled?: boolean
  tabpanelId: string
}

const getButtonStyle = (disabled: boolean, selected: boolean): BetterSystemStyleObject => {
  return {
    bg: 'transparent',
    border: 'none',
    p: 4,
    cursor: disabled && !selected ? 'not-allowed' : 'pointer',
    fontWeight: selected ? 'semibold' : 'inherit',
    color: selected ? 'fg.default' : disabled ? 'fg.subtle' : 'fg.muted',
  }
}

export function IterationsHeader({
  selectedTab,
  setSelectedTab,
  configuration,
  addButtonProps,
  disabled = false,
  tabpanelId,
}: IterationHeaderProps) {
  const activeIterationsCount = configuration.iterations.length
  const completedIterationsCount = configuration.completedIterations.length

  return (
    <div>
      <Box
        sx={{
          ...BaseIterationRowStyle,
        }}
        className={styles.Box}
      >
        <div role="tablist" aria-disabled={disabled} style={{display: 'flex'}}>
          <Button
            sx={getButtonStyle(disabled, selectedTab === 'active')}
            key="active"
            role="tab"
            aria-controls={selectedTab === 'active' ? tabpanelId : undefined}
            {...testIdProps('active-iterations')}
            onClick={() => {
              if (!disabled) setSelectedTab('active')
            }}
            aria-label="Active iterations"
            aria-disabled={disabled}
            aria-selected={selectedTab === 'active'}
            disabled={disabled}
          >
            <Octicon icon={ClockIcon} aria-label="Active iterations" className={styles.Octicon} />
            <span>{activeIterationsCount} Active</span>
          </Button>

          <Button
            sx={getButtonStyle(disabled, selectedTab === 'completed')}
            key="completed"
            role="tab"
            aria-controls={selectedTab === 'completed' ? tabpanelId : undefined}
            {...testIdProps('completed-iterations')}
            onClick={() => {
              if (!disabled) setSelectedTab('completed')
            }}
            aria-label="Completed iterations"
            aria-disabled={disabled}
            aria-selected={selectedTab === 'completed'}
            disabled={disabled}
          >
            <Octicon icon={ArchiveIcon} aria-label="Completed iterations" className={styles.Octicon} />
            <span>{completedIterationsCount} Completed</span>
          </Button>
        </div>
        {selectedTab === 'active' && (
          <div className={styles.Box_1}>
            <NewIterationModalButton {...addButtonProps} />
          </div>
        )}
      </Box>
    </div>
  )
}

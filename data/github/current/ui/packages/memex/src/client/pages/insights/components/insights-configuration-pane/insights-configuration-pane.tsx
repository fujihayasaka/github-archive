import {testIdProps} from '@github-ui/test-id-props'
import {XIcon} from '@primer/octicons-react'
import {Heading, IconButton, Overlay, useFocusTrap} from '@primer/react'

import {useMemexRootHeight} from '../../../../hooks/use-memex-root-height'
import type {ChartState} from '../../../../state-providers/charts/use-charts'
import {useInsightsConfigurationPane} from '../../hooks/use-insights-configuration-pane'
import {ActionButtons} from './action-buttons'
import styles from './insights-configuration-pane.module.css'
import {LayoutSelector} from './layout-selector'
import {XAxisSelector} from './x-axis-selector'
import {YAxisSelector} from './y-axis-selector'

const InsightsConfigurationPaneForm = ({chart}: {chart: ChartState}) => {
  return (
    <div>
      <div className={styles.Box}>
        <LayoutSelector chart={chart} />
        <XAxisSelector chart={chart} />
        <YAxisSelector chart={chart} />
      </div>
      <div className={styles.Box_1}>
        <ActionButtons chart={chart} />
      </div>
    </div>
  )
}

export const InsightsConfigurationPane = ({
  chart,
  returnFocusRef,
}: {
  chart: ChartState
  returnFocusRef: React.RefObject<HTMLButtonElement>
}) => {
  const {closePane, isOpen} = useInsightsConfigurationPane()
  const appHeight = useMemexRootHeight()
  const {containerRef} = useFocusTrap()

  if (!isOpen) return null

  return (
    <Overlay returnFocusRef={returnFocusRef} onEscape={closePane} onClickOutside={closePane}>
      <div
        ref={containerRef as React.RefObject<HTMLDivElement>}
        style={{
          height: appHeight.clientHeight,
        }}
        className={styles.Box_2}
        {...testIdProps('insights-configuration-pane')}
      >
        <div className={styles.Box_3}>
          <Heading as="h2" className={styles.Heading}>
            Configure chart
          </Heading>
          <IconButton
            aria-label="Close configuration pane"
            variant="invisible"
            icon={XIcon}
            onClick={closePane}
            className={styles.IconButton}
            {...testIdProps('side-panel-button-close')}
          />
        </div>
        <InsightsConfigurationPaneForm chart={chart} />
      </div>
    </Overlay>
  )
}

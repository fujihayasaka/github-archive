import {testIdProps} from '@github-ui/test-id-props'
import {Button} from '@primer/react'

import {useInsightsConfigurationPane} from '../../hooks/use-insights-configuration-pane'
import {BaseChartError} from './base-chart-error'
import styles from './invalid-config-error.module.css'

export const InvalidConfigError = () => {
  const {openPane} = useInsightsConfigurationPane()

  return (
    <BaseChartError
      {...testIdProps('chart-invalid-config-error')}
      heading="This chart configuration is no longer valid"
      content={'A required field may have been deleted. Update the configuration or delete the chart.'}
    >
      <Button onClick={openPane} className={styles.Button}>
        Update configuration
      </Button>
    </BaseChartError>
  )
}

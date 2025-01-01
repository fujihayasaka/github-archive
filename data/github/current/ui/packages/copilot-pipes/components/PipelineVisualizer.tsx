import {BasicView} from './views/BasicView'
import {DashboardView} from './views/DashboardView'
import {ListView} from './views/ListView'
import {CompactView} from './views/CompactView'

type ViewType = 'basic' | 'dashboard' | 'list' | 'compact'

interface PipelineVisualizerProps {
  view: ViewType
}

export const PipelineVisualizer: React.FC<PipelineVisualizerProps> = ({view}) => {
  return (
    <>
      {view === 'basic' ? (
        <BasicView />
      ) : view === 'dashboard' ? (
        <DashboardView />
      ) : view === 'list' ? (
        <ListView />
      ) : view === 'compact' ? (
        <CompactView />
      ) : null}
    </>
  )
}

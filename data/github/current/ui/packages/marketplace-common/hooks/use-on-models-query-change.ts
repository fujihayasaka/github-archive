import {useCallback} from 'react'
import {useModelsTask} from '../contexts/ModelsTaskContext'
import {useModelsPublisher} from '../contexts/ModelsPublisherContext'
import {allPublishersOption, allTasksOptionID} from '../utilities/model-filter-options'

export function useOnModelsQueryChange() {
  const {setPublisher} = useModelsPublisher()
  const {setTask} = useModelsTask()

  const onModelsQueryChange = useCallback(() => {
    setTask(allTasksOptionID)
    setPublisher(allPublishersOption)
  }, [setPublisher, setTask])

  return onModelsQueryChange
}

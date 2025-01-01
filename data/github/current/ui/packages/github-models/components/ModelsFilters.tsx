import {ActionList, ActionMenu} from '@primer/react'
import {useCategory} from '@github-ui/marketplace-common/CategoryContext'
import {useModelsTask} from '@github-ui/marketplace-common/ModelsTaskContext'
import {
  allCategoriesOptionID,
  taskOptions,
  publisherOptions,
  categoryOptions,
  selectedTaskName,
} from '@github-ui/marketplace-common/model-filter-options'
import {normalizeModelPublisher} from '../utils/normalize-model-strings'
import {ModelsSortMenu} from './ModelsSortMenu'
import {useModelsPublisher} from '@github-ui/marketplace-common/ModelsPublisherContext'

export default function ModelsFilters() {
  const {publisher, setPublisher} = useModelsPublisher()
  const {task, setTask} = useModelsTask()
  const {category, setCategory} = useCategory()

  const onTaskChange = (newTask: string) => {
    setTask(newTask)
  }

  const onPublisherChange = (newPublisher: string) => {
    setPublisher(newPublisher)
  }

  const onCategoryChange = (newCategory: string) => {
    setCategory(newCategory)
  }

  const categoryName = categoryOptions.find(option => option.id === category)?.name

  return (
    <div className="d-flex gap-2 flex-wrap">
      <ActionMenu>
        <ActionMenu.Button data-testid="family-button">
          <span className="fgColor-muted">Publisher:</span> {normalizeModelPublisher(publisher || '')}
        </ActionMenu.Button>
        <ActionMenu.Overlay width="small">
          <ActionList selectionVariant="single" data-testid="creator-menu">
            {publisherOptions.map(option => (
              <ActionList.Item key={option} selected={option === publisher} onSelect={() => onPublisherChange(option)}>
                {normalizeModelPublisher(option)}
              </ActionList.Item>
            ))}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      <ActionMenu>
        <ActionMenu.Button data-testid="task-button">
          <span className="fgColor-muted">Capability:</span> {selectedTaskName(task)}
        </ActionMenu.Button>
        <ActionMenu.Overlay width="small">
          <ActionList selectionVariant="single" data-testid="creator-menu">
            {taskOptions.map(({id, name}) => (
              <ActionList.Item key={id} selected={id === task} onSelect={() => onTaskChange(id)}>
                {name}
              </ActionList.Item>
            ))}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      <ActionMenu>
        <ActionMenu.Button data-testid="category-button">
          <span className="fgColor-muted">Category:</span> {categoryName || 'All'}
        </ActionMenu.Button>
        <ActionMenu.Overlay width="small">
          <ActionList selectionVariant="single" data-testid="creator-menu">
            {categoryOptions.map(option => (
              <ActionList.Item
                key={option.id}
                // Default to "All" if no category is selected. We can't do this with default state
                // because `category` is shared between models and apps/actions
                selected={option.id === category || (option.id === allCategoriesOptionID && !category)}
                onSelect={() => onCategoryChange(option.id)}
              >
                {option.name}
              </ActionList.Item>
            ))}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      <ModelsSortMenu />
    </div>
  )
}

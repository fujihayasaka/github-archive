import {ActionList, ActionMenu} from '@primer/react'
import {useCategory} from '@github-ui/marketplace-common/CategoryContext'
import {useModelsTask} from '@github-ui/marketplace-common/ModelsTaskContext'
import {
  allCategoriesOptionID,
  allPublishersOption,
  taskOptions,
  publisherOptions,
  categoryOptions,
  selectedTaskName,
} from '@github-ui/marketplace-common/model-filter-options'
import {normalizeModelPublisher} from '../utils/normalize-model-strings'
import {ModelsSortMenu} from './ModelsSortMenu'
import {useModelsPublisher} from '@github-ui/marketplace-common/ModelsPublisherContext'
import {usePage} from '@github-ui/marketplace-common/PageContext'
import {testIdProps} from '@github-ui/test-id-props'

export default function ModelsFilters() {
  const {publisher, setPublisher} = useModelsPublisher()
  const {task, setTask} = useModelsTask()
  const {category, setCategory} = useCategory()
  const {setPage} = usePage()

  const onTaskChange = (newTask: string) => {
    setPage(1)
    setTask(newTask)
  }

  const onPublisherChange = (newPublisher: string) => {
    setPage(1)
    setPublisher(newPublisher)
  }

  const onCategoryChange = (newCategory: string) => {
    setPage(1)
    setCategory(newCategory)
  }

  const categoryName = categoryOptions.find(option => option.id === category)?.name

  const sortedPublisherOptions = [...publisherOptions].sort((a, b) => {
    // Keep the first element in its original position
    if (a === allPublishersOption) return -1
    if (b === allPublishersOption) return 1

    // Normalize the publisher names for comparison
    const normalizedA = normalizeModelPublisher(a)
    const normalizedB = normalizeModelPublisher(b)
    return normalizedA.localeCompare(normalizedB)
  })

  return (
    <div className="d-flex gap-2 flex-wrap">
      <ActionMenu>
        <ActionMenu.Button {...testIdProps('family-button')}>
          <span className="fgColor-muted">Publisher:</span> {normalizeModelPublisher(publisher || '')}
        </ActionMenu.Button>
        <ActionMenu.Overlay width="small">
          <ActionList selectionVariant="single">
            {sortedPublisherOptions.map(option => (
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
          <ActionList selectionVariant="single">
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
          <ActionList selectionVariant="single">
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

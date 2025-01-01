import {ActionList, ActionMenu} from '@primer/react'
import {useFilterContext} from '@github-ui/marketplace-common/FilterContext'
import {taskOptions, modelFamilyOptions, categoryOptions} from '@github-ui/marketplace-common/model-filter-options'
import {normalizeModelPublisher} from '../utils/normalize-model-strings'

export default function ModelsFilters() {
  const {task, setTask, modelFamily, setModelFamily, category, setCategory} = useFilterContext()

  const onTaskChange = (newTask: string) => {
    setTask(newTask)
  }

  const onModelFamilyChange = (newModelFamily: string) => {
    setModelFamily(newModelFamily)
  }

  const onCategoryChange = (newCategory: string) => {
    setCategory(newCategory)
  }

  const categoryName = categoryOptions.find(option => option.id === category)?.name

  return (
    <div className="d-flex gap-2 flex-wrap">
      <ActionMenu>
        <ActionMenu.Button data-testid="family-button">
          <span className="fgColor-muted">By:</span> {normalizeModelPublisher(modelFamily || '')}
        </ActionMenu.Button>
        <ActionMenu.Overlay width="small">
          <ActionList selectionVariant="single" data-testid="creator-menu">
            {modelFamilyOptions.map(option => (
              <ActionList.Item
                key={option}
                selected={option === modelFamily}
                onSelect={() => onModelFamilyChange(option)}
              >
                {normalizeModelPublisher(option)}
              </ActionList.Item>
            ))}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      <ActionMenu>
        <ActionMenu.Button data-testid="task-button">
          <span className="fgColor-muted">Capability:</span>{' '}
          {task?.toLowerCase() === 'chat-completion' ? 'Chat/completion' : task}
        </ActionMenu.Button>
        <ActionMenu.Overlay width="small">
          <ActionList selectionVariant="single" data-testid="creator-menu">
            {taskOptions.map(option => (
              <ActionList.Item key={option} selected={option === task} onSelect={() => onTaskChange(option)}>
                {option.toLowerCase() === 'chat-completion' ? 'Chat/completion' : option}
              </ActionList.Item>
            ))}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      <ActionMenu>
        <ActionMenu.Button data-testid="category-button">
          <span className="fgColor-muted">Tag:</span> {categoryName || 'All'}
        </ActionMenu.Button>
        <ActionMenu.Overlay width="small">
          <ActionList selectionVariant="single" data-testid="creator-menu">
            {categoryOptions.map(option => {
              // Default to "All" if no category is selected. We can't do this with default state
              // because `category` is shared between models and apps/actions
              let selected = option.id === category
              if (option.id === 'All' && !category) {
                selected = true
              }
              return (
                <ActionList.Item key={option.id} selected={selected} onSelect={() => onCategoryChange(option.id)}>
                  {option.name}
                </ActionList.Item>
              )
            })}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </div>
  )
}

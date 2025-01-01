import {ActionList, ActionMenu, Link} from '@primer/react'
import {taskOptions, modelFamilyOptions, categoryOptions} from '@github-ui/marketplace-common/model-filter-options'
import {normalizeModelPublisher} from '../utils/normalize-model-strings'
import {testIdProps} from '@github-ui/test-id-props'

export default function ModelsIndexFilters() {
  return (
    <div className="d-flex gap-2 flex-wrap" {...testIdProps('models-index-filters')}>
      <ActionMenu>
        <ActionMenu.Button data-testid="creator-button">
          <span className="fgColor-muted">By:</span> All providers
        </ActionMenu.Button>
        <ActionMenu.Overlay width="small">
          <ActionList selectionVariant="single" data-testid="creator-menu">
            {modelFamilyOptions.map(option => (
              <Link muted key={option} href={`/marketplace?type=models&model_family=${option}`}>
                <ActionList.Item key={option} selected={option === 'All'}>
                  {normalizeModelPublisher(option)}
                </ActionList.Item>
              </Link>
            ))}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      <ActionMenu>
        <ActionMenu.Button data-testid="creator-button">
          <span className="fgColor-muted">Capability:</span> All
        </ActionMenu.Button>
        <ActionMenu.Overlay width="small">
          <ActionList selectionVariant="single" data-testid="creator-menu">
            {taskOptions.map(option => (
              <Link muted key={option} href={`/marketplace?type=models&task=${option}`}>
                <ActionList.Item key={option} selected={option === 'All'}>
                  {option.toLowerCase() === 'chat-completion' ? 'Chat/completion' : option}
                </ActionList.Item>
              </Link>
            ))}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      <ActionMenu>
        <ActionMenu.Button data-testid="creator-button">
          <span className="fgColor-muted">Tag:</span> All
        </ActionMenu.Button>
        <ActionMenu.Overlay width="small">
          <ActionList selectionVariant="single" data-testid="creator-menu">
            {categoryOptions.map(option => (
              <Link muted key={option.id} href={`/marketplace?type=models&category=${option.id}`}>
                <ActionList.Item key={option.id} selected={option.id === 'All'}>
                  {option.name}
                </ActionList.Item>
              </Link>
            ))}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </div>
  )
}

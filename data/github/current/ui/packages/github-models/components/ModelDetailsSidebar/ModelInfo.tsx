import {ActionList, Button} from '@primer/react'
import type {Model} from '@github-ui/marketplace-common'
import {modelPath} from '@github-ui/paths'
import SidebarInfo from './SidebarInfo'
import {ArrowUpRightIcon} from '@primer/octicons-react'
import {PlaygroundFeedbackBanner} from '../../routes/playground/components/PlaygroundFeedbackBanner'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

interface ModelInfoProps {
  model: Model
  headingLevel: 'h2' | 'h3'
  renderAs: 'button' | 'listitem'
}

export default function ModelInfo({headingLevel, model, renderAs}: ModelInfoProps) {
  const feedbackBannerEnabled = useFeatureFlag('github_models_feedback_banner')

  return (
    <>
      {feedbackBannerEnabled && <PlaygroundFeedbackBanner />}
      <div className="p-0 pb-6 p-md-3 border-bottom">
        <SidebarInfo headingLevel={headingLevel} model={model} />
      </div>
      <div className="p-0 pt-2 px-md-2">
        {renderAs === 'button' ? (
          <Button
            variant="invisible"
            block
            alignContent="start"
            as="a"
            leadingVisual={ArrowUpRightIcon}
            href={modelPath(model)}
          >
            Model details page
          </Button>
        ) : renderAs === 'listitem' ? (
          <ActionList.LinkItem as="a" href={modelPath(model)}>
            <ActionList.LeadingVisual>
              <ArrowUpRightIcon className="fgColor-muted" />
            </ActionList.LeadingVisual>
            Model details page
          </ActionList.LinkItem>
        ) : null}
      </div>
    </>
  )
}

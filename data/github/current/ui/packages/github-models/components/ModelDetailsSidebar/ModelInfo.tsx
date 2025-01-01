import {ActionList, Button} from '@primer/react'
import type {Model} from '@github-ui/marketplace-common'
import {modelPath} from '@github-ui/paths'
import SidebarInfo from './SidebarInfo'
import {ArrowUpRightIcon} from '@primer/octicons-react'

interface ModelInfoProps {
  model: Model
  headingLevel: 'h2' | 'h3'
  renderAs: 'button' | 'listitem'
}

export default function ModelInfo({headingLevel, model, renderAs}: ModelInfoProps) {
  return (
    <>
      <div className="p-0 pb-6 p-md-3 border-bottom">
        <SidebarInfo headingLevel={headingLevel} model={model} />
      </div>
      <div className="p-0 py-2 px-md-2">
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

import {ActionList} from '@primer/react'
import type {Model} from '@github-ui/marketplace-common'
import SidebarInfo from './SidebarInfo'
import {ArrowUpRightIcon} from '@primer/octicons-react'
import {ModelUrlHelper} from '../../../utils/model-url-helper'

interface ModelInfoProps {
  model: Model
  headingLevel: 'h2' | 'h3'
}

export default function ModelInfo({headingLevel, model}: ModelInfoProps) {
  return (
    <>
      <div className="p-0 pb-6 p-md-3 border-bottom">
        <SidebarInfo headingLevel={headingLevel} model={model} />
      </div>
      <div className="p-0 pt-2 px-md-2">
        <ActionList.Item as="a" href={ModelUrlHelper.modelUrl(model)}>
          <ArrowUpRightIcon className="mr-2 fgColor-muted" />
          Model details page
        </ActionList.Item>
      </div>
    </>
  )
}

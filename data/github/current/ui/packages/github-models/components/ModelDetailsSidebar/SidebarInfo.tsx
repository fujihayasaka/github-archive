import {testIdProps} from '@github-ui/test-id-props'
import SidebarHeading from '@github-ui/marketplace-common/SidebarHeading'
import type {Model} from '@github-ui/marketplace-common'
import {TagsSection} from './TagsSection'
import {LanguagesSection} from './LanguagesSection'
import {ModelDetails} from './ModelDetails'

interface SidebarInfoProps {
  model: Model
  headingLevel?: 'h2' | 'h3'
}

export default function SidebarInfo({headingLevel = 'h3', model}: SidebarInfoProps) {
  const {task, summary, tags} = model
  const labels = {tags, task}
  const languages = model.supported_languages.filter(language => language !== null)

  return (
    <div className="d-flex flex-column gap-4" {...testIdProps('sidebar-info')}>
      <div className="d-flex flex-column gap-2">
        <SidebarHeading htmlTag={headingLevel} title="About" />
        <div {...testIdProps('summary')}>{summary}</div>
      </div>
      <ModelDetails model={model} />
      {(labels.tags.length > 0 || labels.task) && <TagsSection headingLevel={headingLevel} labels={labels} />}
      {languages.length > 0 && <LanguagesSection headingLevel={headingLevel} languages={languages} />}
    </div>
  )
}

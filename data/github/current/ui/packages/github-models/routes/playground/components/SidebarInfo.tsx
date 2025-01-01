import {testIdProps} from '@github-ui/test-id-props'
import {Text, Box} from '@primer/react'
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
    <Box
      sx={{
        display: 'flex',
        flexDirection: 'column',
        gap: 4,
      }}
    >
      <Box
        sx={{
          display: 'flex',
          flexDirection: 'column',
          gap: 2,
        }}
      >
        <SidebarHeading htmlTag={headingLevel} title="About" />
        <Text {...testIdProps('summary')} sx={{lineHeight: 1.5}}>
          {summary}
        </Text>
      </Box>
      <ModelDetails model={model} />
      {(labels.tags.length > 0 || labels.task) && <TagsSection headingLevel={headingLevel} labels={labels} />}
      {languages.length > 0 && <LanguagesSection headingLevel={headingLevel} languages={languages} />}
    </Box>
  )
}

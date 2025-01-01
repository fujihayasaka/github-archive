import {SimpleListView} from '@github-ui/simple-list-view'
import {SimpleListHeader} from '@github-ui/simple-list-view/SimpleListHeader'
import {SimpleListItem} from '@github-ui/simple-list-view/SimpleListItem'
import {ProjectTemplateIcon} from '@primer/octicons-react'
import {Box} from '@primer/react'
import {useState} from 'react'

import type {CustomTemplate} from '../../api/common-contracts'
import {sanitizeTextInputHtmlString} from '../../helpers/sanitize'
import {Link} from '../../router'
import {useTemplateLink} from './hooks/use-template-link'
import styles from './temple-list.module.css'

function TemplateListItem({template}: {template: CustomTemplate}) {
  const to = useTemplateLink({type: 'custom', template})
  const [isHovered, setIsHovered] = useState(false)

  return (
    <SimpleListItem>
      <SimpleListItem.LeadingVisual>
        <Box
          sx={{
            color: 'fg.muted',
          }}
        >
          <ProjectTemplateIcon />
        </Box>
      </SimpleListItem.LeadingVisual>
      <SimpleListItem.Title>
        <Link
          to={to}
          style={{
            color: isHovered ? 'var(--fgColor-accent)' : 'var(--fgColor-default)',
          }}
          onMouseEnter={() => setIsHovered(true)}
          onMouseLeave={() => setIsHovered(false)}
        >
          {sanitizeTextInputHtmlString(template.projectTitle)}
        </Link>
      </SimpleListItem.Title>
      {template.projectShortDescription && (
        <SimpleListItem.Description>{template.projectShortDescription}</SimpleListItem.Description>
      )}
    </SimpleListItem>
  )
}

export function TemplateList({
  title,
  templates,
  metadata,
}: {
  /** accessible name for the list view */
  title: string
  templates: Array<CustomTemplate>
  metadata?: React.ReactNode
}) {
  return (
    <Box sx={{borderWidth: 1, borderStyle: 'solid', borderRadius: 2, borderColor: 'border.default'}}>
      <SimpleListView>
        <SimpleListHeader>
          <SimpleListHeader.Title className={styles.title} headingLevel="h3">
            {title}
          </SimpleListHeader.Title>
          <SimpleListHeader.Metadata className={styles.metadata}>{metadata}</SimpleListHeader.Metadata>
        </SimpleListHeader>
        <SimpleListView.Items>
          {templates.map(template => (
            <TemplateListItem key={template.projectNumber} template={template} />
          ))}
        </SimpleListView.Items>
      </SimpleListView>
    </Box>
  )
}

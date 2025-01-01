import {ActionList} from '@primer/react'
import {LinkIcon, ThumbsupIcon, OrganizationIcon} from '@primer/octicons-react'

import styles from './SidebarSocialLinks.module.css'

function SidebarSocialLinks() {
  return (
    <div className={styles.Box}>
      <ActionList variant="full" className={styles.ActionList}>
        <ActionList.Item>
          <ActionList.LeadingVisual>
            <OrganizationIcon />
          </ActionList.LeadingVisual>
          GitHub
        </ActionList.Item>
        <ActionList.Item>
          <ActionList.LeadingVisual>
            <LinkIcon />
          </ActionList.LeadingVisual>
          github.com
        </ActionList.Item>
        <ActionList.Item>
          <ActionList.LeadingVisual>
            <ThumbsupIcon />
          </ActionList.LeadingVisual>
          GitHub
        </ActionList.Item>
      </ActionList>
    </div>
  )
}

export default SidebarSocialLinks

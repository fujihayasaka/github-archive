import {IssuesLoadingSkeleton} from '@github-ui/issues-loading-skeleton'
import styles from './ProjectsSections.module.css'

export function ProjectItemSectionFieldsLoading() {
  return (
    <ul className={styles.FieldListUl}>
      <li style={{margin: '0 2 2 3'}}>
        <ProjectFieldLoading />
        <ProjectFieldLoading />
        <ProjectFieldLoading />
      </li>
    </ul>
  )
}

function ProjectFieldLoading() {
  return (
    <span
      style={{display: 'flex', flexDirection: 'row', alignItems: 'flex-start', gap: 5, width: '100%', marginTop: 2}}
    >
      <IssuesLoadingSkeleton height="md" width="25%" />
      <IssuesLoadingSkeleton height="md" width="40%" />
    </span>
  )
}

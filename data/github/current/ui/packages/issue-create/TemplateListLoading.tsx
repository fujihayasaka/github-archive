import {IssuesLoadingSkeleton} from '@github-ui/issues-loading-skeleton'
import {useIssueCreateConfigContext} from './contexts/IssueCreateConfigContext'
import styles from './TemplateList.module.css'

const loadingSkeletonWidths = ['220px', '250px', '290px', '210px'].map((width, index) => ({
  id: `skeleton-${index}`,
  width,
}))

export function TemplateListLoading() {
  const {optionConfig} = useIssueCreateConfigContext()

  return (
    <div className={`${styles.skeletonContainer} ${optionConfig.insidePortal && 'ml-3'}`}>
      {loadingSkeletonWidths.map(({id, width}) => (
        <IssuesLoadingSkeleton key={id} height="xl" width={width} />
      ))}
    </div>
  )
}

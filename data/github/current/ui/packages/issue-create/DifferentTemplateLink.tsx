import type {IssueFormRef} from '@github-ui/issue-form/Types'
import {LABELS} from './constants/labels'
import {useIssueCreateDataContext} from './contexts/IssueCreateDataContext'
import {useSafeClose} from './hooks/use-safe-close'
import styles from './IssueCreatePage.module.css'
import {getChooseTemplateUrl} from './utils/urls'
import {Link} from '@primer/react'
import {useNavigate} from '@github-ui/use-navigate'

type DifferentTemplateLinkProps = {
  templateName?: string
  nameWithOwner: string
  issueFormRef: React.RefObject<IssueFormRef>
}

export const DifferentTemplateLink = ({templateName, nameWithOwner, issueFormRef}: DifferentTemplateLinkProps) => {
  const navigate = useNavigate()
  const {usedStorageKeyPrefix} = useIssueCreateDataContext()

  const {onSafeClose} = useSafeClose({
    storageKeyPrefix: usedStorageKeyPrefix,
    issueFormRef,
    onCancel: () => {
      // maybe here clear metadata title and body
      navigate(getChooseTemplateUrl(nameWithOwner))
    },
  })

  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'row',
        alignItems: 'center',
        gap: 2,
        marginBottom: 2,
      }}
    >
      <span className="fgColor-muted">{templateName || LABELS.blankIssueName}</span> ·
      <Link inline={false} onClick={onSafeClose} className={styles.chooseTemplateLink}>
        {LABELS.issueCreateChooseDiffTemplate}
      </Link>
    </div>
  )
}

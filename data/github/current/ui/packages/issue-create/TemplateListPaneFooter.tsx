import styles from './TemplateListPaneFooter.module.css'
import {Link} from '@primer/react'
import {LABELS} from './constants/labels'
import {useIssueCreateConfigContext} from './contexts/IssueCreateConfigContext'
import {clsx} from 'clsx'
import {useFragment} from 'react-relay'
import {graphql} from 'relay-runtime'
import type {TemplateListPaneFooter$key} from './__generated__/TemplateListPaneFooter.graphql'

type TemplateListPaneFooterProps = {
  repository: TemplateListPaneFooter$key
}

export const TemplateListPaneFooter = ({repository}: TemplateListPaneFooterProps) => {
  const data = useFragment(
    graphql`
      fragment TemplateListPaneFooter on Repository {
        viewerCanPush
        viewerIssueCreationPermissions {
          typeable
          triageable
        }
        templateTreeUrl
      }
    `,
    repository,
  )

  const {optionConfig} = useIssueCreateConfigContext()
  const canIssueType = data.viewerIssueCreationPermissions.typeable && data.viewerIssueCreationPermissions.triageable

  const hyperlinkText = data.viewerCanPush ? LABELS.editTemplates : LABELS.viewTemplates

  return (
    <div
      className={clsx({
        [styles.insidePortal]: optionConfig.insidePortal,
      })}
    >
      <div
        className={clsx({
          [styles.fullscreen]: !optionConfig.insidePortal,
          [styles.templateFooterWrapper]: true,
        })}
      >
        {canIssueType && <span>You can now add issue types to your forms and templates! </span>}
        <Link href={data.templateTreeUrl} className={styles.link}>
          {hyperlinkText}
        </Link>
      </div>
    </div>
  )
}

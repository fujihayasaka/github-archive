import styles from './TemplateListPaneFooter.module.css'
import {Link} from '@primer/react'
import {useIssueCreateConfigContext} from './contexts/IssueCreateConfigContext'
import {clsx} from 'clsx'
import {ssrSafeLocation} from '@github-ui/ssr-utils'

const COPILOT_CREATE_ISSUE_URL = '/copilot?prompt=Create an issue to ....'

export const TemplateListPaneFooter = () => {
  const {optionConfig} = useIssueCreateConfigContext()

  return (
    <div className={clsx(styles.insidePortal && {[styles.insidePortal]: optionConfig.insidePortal})}>
      <div
        className={clsx(
          styles.fullscreen && {[styles.fullscreen]: !optionConfig.insidePortal},
          styles.templateFooterWrapper && {[styles.templateFooterWrapper]: true},
        )}
      >
        {<span>Save time by creating issues with Copilot. </span>}
        <Link href={new URL(COPILOT_CREATE_ISSUE_URL, ssrSafeLocation.origin).toString()} className={styles.link}>
          Get started.
        </Link>
      </div>
    </div>
  )
}

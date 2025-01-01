import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {repoCodeQualityShowRoute} from './repo-code-quality-show-route'
import {Breadcrumbs, Heading} from '@primer/react'
import {codeQualityIndexPath} from '@github-ui/paths'
import {formatDate} from '../utils/format-date'
import {RuleCategoryBadge} from '../components/RuleCategoryBadge'
import {RuleSeverityBadge} from '../components/RuleSeverityBadge'
import {ExpandableContent} from '../components/ExpandableContent'
import {MarkdownRenderer} from '@github-ui/copilot-markdown'
import {RuleFindings} from '../components/RuleFindings'

import styles from './RepoCodeQualityShow.module.css'
import {Blankslate} from '@primer/react/experimental'
import {CodeSquareIcon} from '@primer/octicons-react'

export function RepoCodeQualityShow() {
  const payload = useRouteQuery(repoCodeQualityShowRoute, 'mainQuery')
  const {owner, repo, ruleId, ruleTitle, ruleDescription, ruleHelp, ruleCategory, ruleSeverity, lastScanAt, fileCount} =
    payload.data

  const ruleHelpMarkdown = <MarkdownRenderer markdown={ruleHelp} />

  return (
    <>
      <Breadcrumbs className="mb-2">
        <Breadcrumbs.Item href={codeQualityIndexPath({owner, repo})}>Code quality</Breadcrumbs.Item>
        <Breadcrumbs.Item selected>{ruleTitle}</Breadcrumbs.Item>
      </Breadcrumbs>
      <div className="d-flex flex-items-center gap-2">
        <Heading as="h1">{ruleTitle}</Heading>
      </div>
      <span className="color-fg-muted f8">Last scan: {formatDate(new Date(lastScanAt))}</span>
      {fileCount === 0 && (
        <Blankslate className="border rounded-2 mt-3">
          <Blankslate.Visual>
            <CodeSquareIcon className="mb-2" size="medium" />
          </Blankslate.Visual>
          <Blankslate.Heading>Finding is no longer available!</Blankslate.Heading>
          <Blankslate.Description>This code quality finding doesn&apos;t exist anymore.</Blankslate.Description>
        </Blankslate>
      )}
      {fileCount > 0 && (
        <div className="d-flex pt-3">
          <div className="col-9 pr-4">
            <ExpandableContent collapsedContent={ruleDescription} expandedContent={ruleHelpMarkdown} />
            <RuleFindings owner={owner} repo={repo} ruleId={ruleId} fileCount={fileCount} />
          </div>
          <div className="col-3 pl-3 color-border-muted">
            <div className="mb-4">
              <p className="mb-1 color-fg-muted f6">
                <strong>Category</strong>
              </p>
              <RuleCategoryBadge category={ruleCategory} />
            </div>
            <hr className={styles.line} />
            <div>
              <p className="mb-1 color-fg-muted f6">
                <strong>Severity</strong>
              </p>
              <RuleSeverityBadge severity={ruleSeverity} />
            </div>
            <hr className={styles.line} />
          </div>
        </div>
      )}
    </>
  )
}

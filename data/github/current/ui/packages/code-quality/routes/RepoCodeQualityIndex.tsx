import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {repoCodeQualityIndexRoute} from './repo-code-quality-index-route'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {Heading} from '@primer/react'
import {formatDate} from '../utils/format-date'
import {Metric} from '../components/Metric'
import DataCard from '@github-ui/data-card'
import {RuleGroupList} from '../components/RuleGroupList'
import {Blankslate} from '@primer/react/experimental'
import {CodeSquareIcon} from '@primer/octicons-react'

export function RepoCodeQualityIndex() {
  const payload = useRouteQuery(repoCodeQualityIndexRoute, 'mainQuery')
  const {owner, repo, lastScanAt, maintainability, reliability} = payload.data

  const totalFindings = maintainability.findingsCount + reliability.findingsCount

  return (
    <>
      <div className="d-flex flex-items-center flex-justify-between mb-1">
        <div className="d-flex flex-items-center gap-2">
          <Heading as="h2">Code quality</Heading>
          <BetaLabel feedbackUrl="#" />
        </div>
        <span className="color-fg-muted f8">Last scan: {formatDate(new Date(lastScanAt))}</span>
      </div>
      <p className="fgColor-muted">Improve the quality of the code in your repositories.</p>
      <div className="d-flex flex-auto flex-column flex-md-row gap-2 pt-1 mb-4">
        <Metric title="Maintainability" data={totalFindings > 0 ? maintainability : undefined} />
        <Metric title="Reliability" data={totalFindings > 0 ? reliability : undefined} />
        <DataCard cardTitle="Total findings">
          <p className="color-fg-subtle f4 font-light lh-condensed">{totalFindings > 0 ? totalFindings : 'No data'}</p>
        </DataCard>
      </div>
      {totalFindings > 0 ? (
        <RuleGroupList owner={owner} repo={repo} findingsCount={totalFindings} />
      ) : (
        <Blankslate className="border rounded-2">
          <Blankslate.Visual>
            <CodeSquareIcon className="mb-2" size="medium" />
          </Blankslate.Visual>
          <Blankslate.Heading>No findings available!</Blankslate.Heading>
          <Blankslate.Description>
            This repository doesn&apos;t have code quality findings yet. Please come back later.
          </Blankslate.Description>
        </Blankslate>
      )}
    </>
  )
}

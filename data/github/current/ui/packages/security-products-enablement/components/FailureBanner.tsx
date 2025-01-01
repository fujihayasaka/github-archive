import {Link as PrimerLink} from '@primer/react'
import {Link} from '@github-ui/react-core/link'
import {Banner} from '@primer/react/experimental'
import type {FailureCounts} from '../security-products-enablement-types'
import pluralize from 'pluralize'
import {useAppContext} from '../contexts/AppContext'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {dismissFailureBannerPath} from '../utils/banner-helper'

export interface FailureBannerProps {
  closeFn: (arg0: boolean) => void
  failureCounts: FailureCounts
  updateQuery: (q: string, p: number) => void
}

const FailureBanner: React.FC<FailureBannerProps> = ({closeFn, failureCounts, updateQuery}) => {
  const {organization: org} = useAppContext()

  if (Object.keys(failureCounts).length === 0) {
    return <></>
  }

  const onDismiss = async () => {
    const result = await verifiedFetch(dismissFailureBannerPath({org}), {method: 'POST'})
    if (result.ok) closeFn(true)
  }

  const totalFailureCount = Object.values(failureCounts).reduce((memo, failCount) => memo + failCount, 0)
  const pluralRepos = pluralize('repository', totalFailureCount, true)
  const numberOfReasons = Object.keys(failureCounts).length

  const setSearchQuery = (event: React.MouseEvent<HTMLAnchorElement>) => {
    event.preventDefault() // we don't actually won't to navigate anywhere
    updateQuery('config-status:failed', 1)
  }
  const viewAllLink = (
    <PrimerLink as={Link} to="#" onClick={setSearchQuery} className="Link--inTextBlock">
      View all failed repositories
    </PrimerLink>
  )

  let innerText
  let title
  let hideTitle = false
  if (numberOfReasons > 1) {
    title = `${pluralRepos} failed to apply:`
    innerText = (
      <>
        <ul className="ml-4 py-2">
          {Object.entries(failureCounts).map(([failText, count], i) => {
            return (
              // eslint-disable-next-line @eslint-react/no-array-index-key
              <li key={i}>
                {pluralize('repository', count, true)} failed because {failText}.
              </li>
            )
          })}
        </ul>
        {viewAllLink}
      </>
    )
  } else {
    const failText = Object.keys(failureCounts)[0]
    title = `${pluralRepos} failed to apply`
    hideTitle = true
    innerText = (
      <>
        {pluralRepos} failed to apply because {failText}. {viewAllLink}.
      </>
    )
  }

  return (
    <Banner
      data-testid="failure-banner"
      onDismiss={onDismiss}
      title={title}
      hideTitle={hideTitle}
      description={innerText}
      variant="warning"
      className="mb-3"
    />
  )
}

export default FailureBanner

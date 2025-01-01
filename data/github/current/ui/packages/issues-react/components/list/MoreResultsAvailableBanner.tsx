import {Banner} from '@primer/react/experimental'
import {MESSAGES} from '../../constants/messages'
import {VALUES} from '../../constants/values'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {isPrsOnly} from '@github-ui/query-builder/utils/query'
import {useQueryContext} from '../../contexts/QueryContext'
import {useMemo} from 'react'
import {useUser} from '@github-ui/use-user'

export type MoreResultsAvailableBannerProps = {
  itemsLabel: string
}

export const MoreResultsAvailableBanner = ({itemsLabel}: MoreResultsAvailableBannerProps) => {
  const {activeSearchQuery} = useQueryContext()
  const {currentUser} = useUser()
  const onlyPrs = useMemo(() => isPrsOnly(activeSearchQuery), [activeSearchQuery])
  const bypassEsLimits = useFeatureFlag('issues_react_bypass_es_limits')
  return (
    <div className="p-2">
      <Banner
        description={MESSAGES.moreItemsAvailableDescription(
          VALUES.maxIssuesListItems(bypassEsLimits, onlyPrs, !!currentUser),
          itemsLabel,
        )}
        hideTitle
        title={MESSAGES.moreItemsAvailableTitle(itemsLabel)}
      />
    </div>
  )
}

import DataCard from '@github-ui/data-card'
import {CodescanCheckmarkIcon} from '@primer/octicons-react'

import {formatFriendly} from '../../../common/utils/number-formatter'
import styles from './AutofixSuggestionsCard.module.css'
import useAutofixSuggestionsQuery, {type UseAutofixSuggestionsQueryParams} from './use-autofix-suggestions-query'

interface AutofixSuggestionsCardProps extends UseAutofixSuggestionsQueryParams {}

export default function AutofixSuggestionsCard(props: AutofixSuggestionsCardProps): JSX.Element {
  const dataQuery = useAutofixSuggestionsQuery(props)

  return (
    <DataCard cardTitle="Copilot Autofix suggestions" loading={dataQuery.isPending} error={dataQuery.isError}>
      {dataQuery.isSuccess && (
        <>
          <div className={styles.Box}>
            <CodescanCheckmarkIcon size="medium" className="fgColor-attention" />
            <DataCard.Counter count={dataQuery.data.count} />
          </div>
          <DataCard.Description>
            {`${formatFriendly(dataQuery.data.percentage)}% of pull request alerts have an autofix suggestion`}
          </DataCard.Description>
        </>
      )}
    </DataCard>
  )
}

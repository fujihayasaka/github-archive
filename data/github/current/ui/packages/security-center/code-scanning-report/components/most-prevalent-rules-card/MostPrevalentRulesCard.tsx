import DataCard from '@github-ui/data-card'
import type {UseQueryResult} from '@github-ui/react-query'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {AlertIcon, ShieldCheckIcon} from '@primer/octicons-react'
import {Box, Button, CounterLabel} from '@primer/react'
import {Dialog} from '@primer/react/deprecated'
import {Blankslate} from '@primer/react/experimental'
import {useEffect, useRef, useState} from 'react'

import {CursorPagination} from '../../../common/components/cursor-pagination'
import styles from '../../../secret-scanning-report/components/AggregateMetricsList.module.css'
import useMostPrevalentRulesQuery, {type MostPrevalentRulesResult} from './use-most-prevalent-rules-query'

const numberFormatter = Intl.NumberFormat('en-US', {notation: 'standard'})

interface MostPrevalentRulesCardProps {
  query: string
  startDate: string
  endDate: string
}

export default function MostPrevalentRulesCard(props: MostPrevalentRulesCardProps): JSX.Element {
  const dataQuery = useMostPrevalentRulesQuery({...props, pageSize: 5})

  return (
    <DataCard cardTitle="Most prevalent rules">
      <RuleList {...{dataQuery}} />
      {dataQuery.data?.next && (
        <>
          <SeeAllDialog {...props} />
        </>
      )}
    </DataCard>
  )
}

export function SeeAllDialog(props: MostPrevalentRulesCardProps): JSX.Element {
  // track paging cursor; reset when query changes
  const [cursor, setCursor] = useState<string | undefined>()
  useEffect(() => setCursor(undefined), [props])

  const [isOpen, setIsOpen] = useState(false)
  const returnFocusRef = useRef(null)

  const dataQuery = useMostPrevalentRulesQuery({...props, cursor, pageSize: 10, enabled: isOpen})

  return (
    <>
      <Button data-testid="trigger-button" ref={returnFocusRef} onClick={() => setIsOpen(true)} variant={'invisible'}>
        See all rules
      </Button>
      <Dialog
        returnFocusRef={returnFocusRef}
        isOpen={isOpen}
        onDismiss={() => setIsOpen(false)}
        aria-labelledby="header"
      >
        <div data-testid="inner">
          <Dialog.Header id="header" sx={{backgroundColor: 'transparent'}}>
            Most prevalent rules
          </Dialog.Header>
          <Box sx={{p: 3}}>
            <RuleList {...{dataQuery}} />
            {dataQuery.isSuccess && (
              <CursorPagination
                previousCursor={dataQuery.data.previous}
                nextCursor={dataQuery.data.next}
                onPageChange={setCursor}
              />
            )}
          </Box>
        </div>
      </Dialog>
    </>
  )
}

interface RuleListProps {
  dataQuery: UseQueryResult<MostPrevalentRulesResult>
}
function RuleList({dataQuery}: RuleListProps): JSX.Element {
  if (dataQuery.isPending) {
    return (
      <ul className={styles.ListFull} data-testid={'loading-container'}>
        {Array(5).map((_, index) => (
          // eslint-disable-next-line @eslint-react/no-array-index-key
          <li className={styles.ListItem} key={index}>
            <LoadingSkeleton as={'div'} variant={'rounded'} height={'md'} width={'random'} sx={{mb: 1}} />
            <LoadingSkeleton as={'div'} variant={'rounded'} height={'sm'} width={'60px'} />
          </li>
        ))}
      </ul>
    )
  }

  if (dataQuery.isError) {
    return (
      <Box data-testid={'error-blankslate'} sx={{py: 9}}>
        <Blankslate>
          <Blankslate.Visual>
            <AlertIcon size="medium" />
          </Blankslate.Visual>
          <Blankslate.Description>Rule information could not be loaded right now</Blankslate.Description>
        </Blankslate>
      </Box>
    )
  }

  if (dataQuery.data.items.length === 0) {
    return (
      <Box data-testid={'empty-blankslate'} sx={{py: 9}}>
        <Blankslate>
          <Blankslate.Visual>
            <ShieldCheckIcon size="medium" />
          </Blankslate.Visual>
          <Blankslate.Description>
            Try modifying your filters to see the security impact on your organization.
          </Blankslate.Description>
        </Blankslate>
      </Box>
    )
  }

  return (
    <ul className={styles.ListFull}>
      {dataQuery.data.items.map(item => (
        <li className={styles.ListItem} key={item.ruleSarifIdentifier}>
          <div>
            <p>{item.ruleName}</p>
            <p className={styles.Description}>{item.ruleSarifIdentifier}</p>
          </div>
          <div>
            <CounterLabel>{numberFormatter.format(item.count)}</CounterLabel>
          </div>
        </li>
      ))}
    </ul>
  )
}

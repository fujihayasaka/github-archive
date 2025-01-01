import {useState} from 'react'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {testIdProps} from '@github-ui/test-id-props'
import {useNavigate} from '@github-ui/use-navigate'
import {Button, Heading} from '@primer/react'
import {clsx} from 'clsx'
import {AccountFilter} from './AccountFilter'
import type {Accounts} from './AccountFilter'
import {EcosystemsFilter} from './EcosystemsFilter'
import type {Ecosystems} from './EcosystemsFilter'
import {OrderingFilter} from './OrderingFilter'
import type {Orderings} from './OrderingFilter'
import {DirectOnlyFilter} from './DirectOnlyFilter'

import styles from './SponsorsExploreFilter.module.css'

export interface SponsorsExploreFilterProps {
  accounts: Accounts
  selectedAccount: string
  ecosystems: Ecosystems
  selectedEcosystems: string[]
  orderings: Orderings
  selectedOrdering: string
  directDependenciesOnly: boolean
}

export function SponsorsExploreFilter({
  accounts,
  selectedAccount,
  ecosystems,
  selectedEcosystems,
  orderings,
  selectedOrdering,
  directDependenciesOnly,
}: SponsorsExploreFilterProps) {
  const [accountFilter, setAccountFilter] = useState<string>(selectedAccount)
  const [ecosystemsFilter, setEcosystemsFilter] = useState<string[]>(selectedEcosystems)
  const [orderingFilter, setOrderingFilter] = useState<string>(selectedOrdering)
  const [directOnlyFilter, setDirectOnlyFilter] = useState<boolean>(directDependenciesOnly)

  const navigate = useNavigate()

  const onSubmit = (e: React.FormEvent<EventTarget>) => {
    e.preventDefault()
    const params = {
      ...(accountFilter && {account: accountFilter}),
      ...(ecosystemsFilter.length && {ecosystems: ecosystemsFilter.join(',')}),
      ...(orderingFilter && {sort_by: orderingFilter}),
      ...(!directOnlyFilter && {direct: '0'}),
    }
    const filterParams = new URLSearchParams(params).toString()

    navigate(`${ssrSafeLocation.pathname}?${filterParams}`)
  }

  return (
    <form onSubmit={onSubmit} {...testIdProps('sponsors-explore-filter')}>
      <Heading as="h2" className={clsx(styles.Heading, styles.Heading_1)}>
        Explore as
      </Heading>
      <div className={styles.Heading_1}>
        <AccountFilter accounts={accounts} accountFilter={accountFilter} setAccountFilter={setAccountFilter} />
      </div>
      <Heading as="h2" className={clsx(styles.Heading, styles.Heading_1)}>
        Ecosystems
      </Heading>
      <div className={styles.Heading_1}>
        <EcosystemsFilter
          ecosystems={ecosystems}
          ecosystemsFilter={ecosystemsFilter}
          setEcosystemsFilter={setEcosystemsFilter}
        />
      </div>
      <Heading as="h2" className={clsx(styles.Heading, styles.Heading_1)}>
        Order by
      </Heading>
      <div className={styles.Heading_1}>
        <OrderingFilter orderings={orderings} orderingFilter={orderingFilter} setOrderingFilter={setOrderingFilter} />
      </div>
      <div className={clsx(styles.Box, styles.Heading_1)}>
        <DirectOnlyFilter directOnlyFilter={directOnlyFilter} setDirectOnlyFilter={setDirectOnlyFilter} />
      </div>
      <div className={clsx(styles.Box_1, styles.Heading_1)}>
        <Button type="submit" variant="primary" {...testIdProps('sponsors-explore-filter-button')}>
          Apply
        </Button>
      </div>
    </form>
  )
}

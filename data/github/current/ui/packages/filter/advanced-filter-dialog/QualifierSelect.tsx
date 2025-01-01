import {TriangleDownIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button, Text} from '@primer/react'
import {clsx} from 'clsx'

import type {FilterProvider, MutableFilterBlock} from '../types'
import {isMutableFilterBlock} from '../utils'
import styles from './QualifierSelect.module.css'

interface QualifierSelectProps {
  filterBlock: MutableFilterBlock
  index: number
  filterProviders: FilterProvider[]
  setFilterProvider: (qualifier: FilterProvider) => void
}

export const QualifierSelect = ({filterBlock, filterProviders, index, setFilterProvider}: QualifierSelectProps) => {
  const LeadingIcon = filterBlock?.provider?.icon
  return (
    <ActionMenu>
      <ActionMenu.Anchor>
        <Button
          id={`afd-row-${index}-qualifier`}
          aria-label={`Qualifier ${index + 1}`}
          className={clsx('advanced-filter-item-qualifier', styles.Button_0)}
          size="small"
          block
          alignContent="start"
          leadingVisual={() => (LeadingIcon ? <LeadingIcon className={styles.Octicon_0} /> : null)}
          trailingAction={() => <TriangleDownIcon className={styles.Octicon_0} />}
        >
          {!isMutableFilterBlock(filterBlock)
            ? Text
            : filterBlock?.provider?.displayName ?? filterBlock?.provider?.key ?? 'Select a filter'}
        </Button>
      </ActionMenu.Anchor>
      <ActionMenu.Overlay className={styles.ActionMenu_Overlay_0}>
        <ActionList selectionVariant="single" className={styles.ActionList_0}>
          {filterProviders.map((provider, id) => {
            const {icon: Icon} = provider
            return (
              <ActionList.Item
                // eslint-disable-next-line @eslint-react/no-array-index-key
                key={`advanced-filter-item-${filterBlock.id}-provider-${provider.key}-${id}`}
                onSelect={() => setFilterProvider(provider)}
                selected={provider.key === filterBlock.provider?.key}
              >
                {Icon && (
                  <ActionList.LeadingVisual>
                    <Icon />
                  </ActionList.LeadingVisual>
                )}
                {provider.displayName ?? provider.key}
              </ActionList.Item>
            )
          })}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}

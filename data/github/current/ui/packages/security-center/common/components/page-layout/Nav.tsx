import {TabNav} from '@primer/react/deprecated'
import {clsx} from 'clsx'

import {useClickLogging} from '../../hooks/use-click-logging'
import styles from './Nav.module.css'

type Props = {
  items: Array<{
    key: string
    label: string
    selected?: boolean
  }>
  onSelectionChanged?: (selected: string) => void
}

function Nav({items, onSelectionChanged}: Props): JSX.Element {
  const {logClick} = useClickLogging({category: 'PageLayout.Nav'})

  return (
    <TabNav className={clsx('mb-4', styles.TabNav)}>
      {items.map(item => (
        <TabNav.Link
          as="button"
          key={item.key}
          selected={item.selected}
          onClick={() => {
            logClick({action: 'select nav tab', label: item.label})
            onSelectionChanged?.(item.key)
          }}
        >
          {item.label}
        </TabNav.Link>
      ))}
    </TabNav>
  )
}

Nav.displayName = 'PageLayout.Nav'

export default Nav

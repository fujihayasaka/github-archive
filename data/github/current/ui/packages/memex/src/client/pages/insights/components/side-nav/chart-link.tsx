import {testIdProps} from '@github-ui/test-id-props'
import {NavList} from '@primer/react'
import {memo} from 'react'

import {PotentiallyDirty} from '../../../../components/potentially-dirty'
import {NavLinkActionListItem} from '../../../../components/react-router/action-list-nav-link-item'
import styles from './chart-link.module.css'

export const ChartLink = memo<
  React.ComponentProps<typeof NavList.Item> & {
    to: string
    isDirty: boolean
    isActive: boolean
    children: string
    trailingVisual?: JSX.Element | null
    leadingVisual?: JSX.Element | null
  }
>(function ChartLink({to, isActive, children, isDirty, leadingVisual = null, trailingVisual = null, ...props}) {
  return (
    <NavLinkActionListItem to={to} isActive={isActive} end {...props}>
      {/* eslint-disable-next-line primer-react/direct-slot-children */}
      {leadingVisual ? <NavList.LeadingVisual>{leadingVisual}</NavList.LeadingVisual> : null}
      <div className={styles.Box}>
        {children}
        {!isActive && isDirty ? (
          <PotentiallyDirty
            isDirty
            hideDirtyState={false}
            className={styles.PotentiallyDirty}
            {...testIdProps('my-chart-navigation-item-dirty')}
          />
        ) : null}
      </div>
      {trailingVisual ? (
        /* eslint-disable-next-line primer-react/direct-slot-children */
        <NavList.TrailingVisual className="pointer-events-auto">{trailingVisual}</NavList.TrailingVisual>
      ) : null}
    </NavLinkActionListItem>
  )
})

import {PageLayout} from '@primer/react'
import {memo} from 'react'

import styles from './insights-layout.module.css'
import {InsightsSideNav} from './side-nav'

export const InsightsLayout = memo<{
  children?: React.ReactNode
}>(function InsightsLayout({children}) {
  return (
    <PageLayout containerWidth="full" className={styles.Container}>
      <PageLayout.Pane position="start" className={styles.Pane}>
        <InsightsSideNav />
      </PageLayout.Pane>
      <PageLayout.Content width="large" className={styles.MainContent}>
        {children}
      </PageLayout.Content>
    </PageLayout>
  )
})

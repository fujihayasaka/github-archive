import {PageLayout} from '@primer/react'
import NavListUser from './NavListUser'
import NavListEnterprise from './NavListEnterprise'
import GlobalNavigation from './GlobalNavigation'
import ContextSwitcher from './ContextSwitcher'

import styles from './SettingsLayout.module.css'

type SettingsPageProps = {
  children?: React.ReactNode
  active?: string
  nav?: 'user' | 'enterprise'
}

const SettingsLayout = ({children, active = '', nav = 'user'}: SettingsPageProps) => {
  return (
    <div className={styles.Box}>
      <GlobalNavigation />
      <PageLayout containerWidth="xlarge" className={styles.PageLayout}>
        <PageLayout.Pane width="large" position="start" className={styles.PageLayout_Pane}>
          <div className={styles.Box_1}>
            {nav === 'user' && (
              <>
                <ContextSwitcher title="tbenning" subtitle="Personal account" />
                <div className={styles.Box_2}>
                  <NavListUser active={active} />
                </div>
              </>
            )}
            {nav === 'enterprise' && (
              <>
                <ContextSwitcher title="Avocado" subtitle="Enterprise account" />
                <div className={styles.Box_2}>
                  <NavListEnterprise active={active} />
                </div>
              </>
            )}
          </div>
        </PageLayout.Pane>
        <PageLayout.Content>
          <SettingsWrapper>{children}</SettingsWrapper>
        </PageLayout.Content>
      </PageLayout>
    </div>
  )
}

type SettingsWrapperProps = {
  children: React.ReactNode
}

const SettingsWrapper = ({children}: SettingsWrapperProps) => {
  return <div className={styles.Box_3}>{children}</div>
}

export {SettingsLayout, SettingsWrapper}

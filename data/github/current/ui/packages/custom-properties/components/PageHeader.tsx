import {isFeatureEnabled} from '@github-ui/feature-flags'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {Label, PageHeader} from '@primer/react'
import type {ReactNode} from 'react'

import styles from './PageHeader.module.css'

interface Props {
  title: ReactNode
  subtitle?: ReactNode
  actions?: ReactNode
  betaLabel?: boolean
}
export function PropertyPageHeader({title, subtitle, actions, betaLabel}: Props) {
  const lifecycleLabelNameEnabled = isFeatureEnabled('lifecycle_label_name_updates')
  const enterpriseNavRedesignEnabled = true
  return (
    <>
      <PageHeader>
        <PageHeader.TitleArea className={styles.PageHeader_TitleArea}>
          <PageHeader.Title as="h2" className="h1-override-shared-component">
            {title}
          </PageHeader.Title>
          {betaLabel && !enterpriseNavRedesignEnabled && (
            <PageHeader.TrailingVisual>
              {lifecycleLabelNameEnabled ? <BetaLabel /> : <Label variant="success">Beta</Label>}
            </PageHeader.TrailingVisual>
          )}
        </PageHeader.TitleArea>
        <PageHeader.Actions>
          {actions ? <div className={styles.actionsContainer}>{actions}</div> : null}
        </PageHeader.Actions>
      </PageHeader>
      {subtitle ? <p className={styles.subtitleText}>{subtitle}</p> : null}
    </>
  )
}

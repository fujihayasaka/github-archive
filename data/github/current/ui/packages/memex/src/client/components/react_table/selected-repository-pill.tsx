import {testIdProps} from '@github-ui/test-id-props'

import type {SuggestedRepository} from '../../api/repository/contracts'
import styles from './selected-repository-pill.module.css'

export const SelectedRepositoryPill = ({repository}: {repository: SuggestedRepository}) => {
  return (
    <div className={styles.Box} {...testIdProps('repo-searcher-selected-repo')}>
      <span className={styles.Text}>repo:</span>
      <span className={styles.Text_1}>{repository.name}</span>
    </div>
  )
}

import {SettingsResources} from '../../../strings'
import styles from './no-iterations-placeholder.module.css'

export function NoIterationsPlaceholder({isActiveTab}: {isActiveTab: boolean}) {
  return (
    <div className={styles.Box}>
      <h3 className={styles.Text}>
        {isActiveTab ? SettingsResources.noIterationsTitle : SettingsResources.noCompletedIterationsTitle}
      </h3>
      <span className={styles.Text_1}>
        {isActiveTab ? SettingsResources.noIterationsDescription : SettingsResources.noCompletedIterationsDescription}
      </span>
    </div>
  )
}

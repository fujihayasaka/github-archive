import CheckRunItem from './CheckRunItem'
import type {CheckRun} from '../index'

import styles from './ChecksStatusBadgeFooter.module.css'

export default function ChecksStatusBadgeFooter({checkRuns}: {checkRuns: CheckRun[]}) {
  return (
    <ul className={styles.Box}>
      {checkRuns.map((checkRun, i) => (
        // This list will not change, so using the index for the key is safe
        // eslint-disable-next-line @eslint-react/no-array-index-key
        <CheckRunItem key={i} checkRun={checkRun} />
      ))}
    </ul>
  )
}

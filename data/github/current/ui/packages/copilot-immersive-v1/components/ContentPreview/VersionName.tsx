import {BranchName} from '@primer/react'

import styles from './VersionName.module.css'

interface VersionNameProps {
  version: number
}

export function VersionName({version}: VersionNameProps) {
  return (
    <BranchName className={styles.version} as="span">
      v{version}
    </BranchName>
  )
}

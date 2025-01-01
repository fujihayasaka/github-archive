import {BranchName} from '@primer/react'

import styles from './VersionName.module.css'

interface VersionNameProps {
  version: number
  'data-testid'?: string
}

export function VersionName({'data-testid': testid, version}: VersionNameProps) {
  return (
    <BranchName className={styles.version} as="span" data-testid={testid}>
      v{version}
    </BranchName>
  )
}

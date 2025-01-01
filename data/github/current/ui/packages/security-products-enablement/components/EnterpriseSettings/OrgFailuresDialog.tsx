import {Dialog} from '@primer/react/experimental'
import {Link as PrimerLink} from '@primer/react'
import {settingsOrgSecurityProductsPath} from '@github-ui/paths'
import {dialogSize} from '../../utils/dialog-helpers'
import type {EnterpriseOrgFailures} from '../../security-products-enablement-types'

import styles from './OrgFailuresDialog.module.css'

interface OrgFailuresDialogProps {
  failures: EnterpriseOrgFailures
  setShowFailedOrgDialog: React.Dispatch<React.SetStateAction<boolean>>
}

export const OrgFailuresDialog: React.FC<OrgFailuresDialogProps> = ({failures, setShowFailedOrgDialog}) => {
  if (!failures || !failures.orgs || failures.totalRepoFailures === 0) return null
  const failedOrgs = failures.orgs.map(({name, repoFailures}, i) => {
    const href = settingsOrgSecurityProductsPath({org: name, q: 'config-status:failed'})
    return (
      <li key={`name${i.toString()}`} style={{marginTop: 4}}>
        <PrimerLink inline href={href} target="_blank" rel="noopener noreferrer">
          {name}
        </PrimerLink>
        <span> ({repoFailures} failed repositories)</span>
      </li>
    )
  })

  return (
    <>
      <Dialog
        title="Organizations with failed applications"
        onClose={() => setShowFailedOrgDialog(false)}
        data-testid="failed-orgs-dialog"
        sx={dialogSize}
      >
        <div className={styles.Box}>
          <p>The following organizations have repositories where configurations failed to apply:</p>
          <ul data-testid="failed-orgs-dialog-list" style={{marginLeft: 20, marginTop: 4}}>
            {failedOrgs}
          </ul>
        </div>
      </Dialog>
    </>
  )
}

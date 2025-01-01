import {useState} from 'react'
import {Heading, Button} from '@primer/react'
import {clsx} from 'clsx'
import styles from './CopilotDangerZone.module.css'
import {CopilotOrganizationDisableAllAccessDialog} from './organizations/CopilotOrganizationDisableAllAccessDialog'

export function CopilotDangerZone() {
  const [isDisableDialogOpen, setIsDisableDialogOpen] = useState<boolean>(false)
  return (
    <>
      <Heading as="h2" className={clsx(styles.dangerZoneHeading)} data-testid="licensing-copilot-danger-zone">
        Danger zone
      </Heading>
      <div className={clsx(styles.dangerZoneBox)}>
        <div className={clsx(styles.dangerZoneDescription)}>
          <Heading as="h3" className={clsx(styles.dangerZoneInnerHeading)}>
            Disable Copilot
          </Heading>
          <p className={clsx(styles.dangerZoneText)}>
            Remove Copilot access for all members and organizations in the entire enterprise
          </p>
        </div>
        <div className={clsx(styles.dangerZoneButton)}>
          <Button variant="danger" data-testid="danger-zone-enable" onClick={() => setIsDisableDialogOpen(true)}>
            Disable
          </Button>
        </div>
        {isDisableDialogOpen && (
          <CopilotOrganizationDisableAllAccessDialog closeDialog={() => setIsDisableDialogOpen(false)} />
        )}
      </div>
    </>
  )
}

import {Dialog, Label, IconButton} from '@primer/react'
import {GlobeIcon, OrganizationIcon, XIcon} from '@primer/octicons-react'
import styles from './CopilotUserLicenseSummaryDialog.module.css'
import type {User} from '../../types'
import {useState} from 'react'
import {CopilotUserChangeAccessDialog} from './CopilotUserChangeAccessDialog'

export interface CopilotUserLicenseSummaryDialogProps {
  user: User
  onClose: () => void
}

export function CopilotUserLicenseSummaryDialog(props: CopilotUserLicenseSummaryDialogProps) {
  const licenses = props.user.licenses || []
  const dominantLicense = props.user.dominantLicense || null
  const [showConfirmationDialog, setShowConfirmationDialog] = useState(false)

  return (
    <>
      <Dialog
        title={`Copilot license assignments for ${props.user.name}`}
        onClose={props.onClose}
        className={styles.dialog}
      >
        <div data-testid={`license-assignment-summary-for-${props.user.id}`}>
          {dominantLicense && (
            <div className={styles.dominantLicenseSection} data-testid={`dominant-license-for-${props.user.id}`}>
              <table className={styles.tableTop}>
                <thead>
                  <tr>
                    <th className={styles.thTop}>Status</th>
                    <th className={styles.thTop}>License</th>
                    <th className={styles.thTop}>Source</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td className={styles.tdTop}>
                      <Label
                        variant={dominantLicense.expirationDate === null ? 'success' : 'attention'}
                        className={styles.label}
                      >
                        {dominantLicense.expirationDate === null ? 'Active' : 'Pending cancellation'}
                      </Label>
                    </td>
                    <td className={styles.tdTop}>
                      Copilot <span>{dominantLicense.planType === 'business' ? 'Business' : 'Enterprise'}</span>
                    </td>
                    <td className={styles.tdTop}>{dominantLicense.ownerName}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          )}

          <h4 className={styles.sectionTitle}>Other license sources</h4>
          <div className={styles.textContainer}>
            <span className="color-fg-muted">
              Users can receive access to Copilot from multiple sources. A user&apos;s organization license can only be
              removed from the organization&apos;s Copilot settings.
            </span>
          </div>

          <table className={styles.tableBottom}>
            <thead>
              <tr>
                <th className={styles.thBottom}>Source</th>
                <th className={styles.thBottom}>License type</th>
                <th className={styles.thBottom}>Expires</th>
                <th className={styles.thBottom} />
              </tr>
            </thead>
            <tbody>
              {licenses.map(license => (
                <tr key={license.ownerId} data-testid={`license-information-for-${license.ownerId}`}>
                  <td className={styles.tdBottom}>
                    {license.ownerType === 'business' ? (
                      <GlobeIcon size={16} aria-label="Enterprise" />
                    ) : (
                      <OrganizationIcon size={16} aria-label="Organization" />
                    )}
                    <span style={{marginLeft: '8px'}}>{license.ownerName}</span>
                  </td>
                  <td className={styles.tdBottom}>
                    <Label variant="default" className={styles.label}>
                      Copilot
                      <span className={styles.licenseType}>
                        {license.planType === 'business' ? 'Business' : 'Enterprise'}
                      </span>
                    </Label>
                  </td>
                  <td className={styles.tdBottom}>
                    <span>{license.expirationDate || '-'}</span>
                  </td>
                  <td className={styles.tdBottom}>
                    {license.ownerType !== 'organization' && license.expirationDate === null ? (
                      <IconButton
                        data-testid={`remove-license-button-${license.ownerId}`}
                        icon={XIcon}
                        aria-label={`Remove license from ${license.ownerName}`}
                        variant="invisible"
                        className={styles.removeButton}
                        onClick={() => {
                          setShowConfirmationDialog(true)
                        }}
                      />
                    ) : null}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Dialog>

      {showConfirmationDialog && (
        <CopilotUserChangeAccessDialog
          users={[props.user.id]}
          downgrade
          onClose={() => {
            setShowConfirmationDialog(false)
          }}
        />
      )}
    </>
  )
}

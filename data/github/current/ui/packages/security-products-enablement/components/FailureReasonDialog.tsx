import {Dialog} from '@primer/react/experimental'
import {Link} from '@primer/react'
import {ENABLEMENT_FAILURES_MAP} from '../utils/helpers'
import {useAppContext} from '../contexts/AppContext'

import styles from './FailureReasonDialog.module.css'

interface FailureReasonDialogProps {
  reason: string
  repositoryName: string
  configurationName: string
  setShowFailureReasonDialog: React.Dispatch<React.SetStateAction<boolean>>
}

interface FailureDialogBodyMap {
  [dialogTitle: string]: {
    body: JSX.Element
    remediations: JSX.Element[]
  }
}

const dialogTitleText = (failureReason: string | undefined) => {
  if (!failureReason) return 'Something went wrong'

  const reason: {frontend_dialog_title?: string} | undefined = ENABLEMENT_FAILURES_MAP.get(failureReason)

  return reason && reason['frontend_dialog_title'] ? reason['frontend_dialog_title'] : 'Something went wrong'
}

const FailureReasonDialog: React.FC<FailureReasonDialogProps> = ({
  reason,
  repositoryName,
  configurationName,
  setShowFailureReasonDialog,
}) => {
  const {docsUrls} = useAppContext()
  const title = dialogTitleText(reason)
  const repositoryNameText = <strong>{repositoryName}</strong>

  const FAILURE_DIALOG_BODY_MAP: FailureDialogBodyMap = {
    'Not enough licenses': {
      body: (
        <>
          {configurationName} is enabling GitHub Advanced Security features but you don’t have enough licenses. As a
          private repository, {repositoryNameText} requires 1 additional GitHub Advanced Security license.
        </>
      ),
      remediations: [
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Purchase more licenses and re-apply this configuration.</>,
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Apply a configuration that excludes GitHub Advanced Security.</>,
      ],
    },
    'Not enough Secret Protection licenses': {
      body: (
        <>
          {configurationName} is enabling Secret Protection features but you don’t have enough licenses. As a private
          repository, {repositoryNameText} requires additional Secret Protection licenses.
        </>
      ),
      remediations: [
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Purchase more Secret Protection licenses and re-apply this configuration.</>,
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Apply a configuration that disables Secret Protection.</>,
      ],
    },
    'Not enough Code Security licenses': {
      body: (
        <>
          {configurationName} is enabling Code Security features but you don’t have enough licenses. As a private
          repository, {repositoryNameText} requires additional Code Security licenses.
        </>
      ),
      remediations: [
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Purchase more Code Security licenses and re-apply this configuration.</>,
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Apply a configuration that disables Code Security.</>,
      ],
    },
    'Code scanning: Actions disabled': {
      body: (
        <>
          {configurationName} is enabling code scanning default setup, which requires actions, but actions is disabled
          at the repository/organization/enterprise level.
        </>
      ),
      remediations: [
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Enable Actions and re-apply this configuration.</>,
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Apply a configuration that delegates code scanning default setup.</>,
      ],
    },
    'Code scanning: Advanced setup conflict': {
      body: (
        <>
          {configurationName} is enabling code scanning default setup but {repositoryNameText} has an existing advanced
          setup.
        </>
      ),
      remediations: [
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Disable advanced setup on {repositoryNameText} and re-apply this configuration.</>,
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Apply a configuration that delegates code scanning default setup.</>,
      ],
    },
    'Code scanning: Runners unavailable': {
      body: (
        <>
          Code scanning default setup can only be enabled if runners with the label <code>code-scanning</code> (or{' '}
          <code>macOS</code> for Swift) are assigned to this repository.
        </>
      ),
      remediations: [
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>
          Create a runner with the label <code>code-scanning</code>.
        </>,
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Ensure that this repository has access to the runner.</>,
      ],
    },
    'Code scanning: Specified runner unavailable': {
      body: (
        <>
          Code scanning default setup can only be enabled if a runner with the specified label is assigned to this
          repository.
        </>
      ),
      remediations: [
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Create a runner with the label specified in this configuration.</>,
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Ensure that this repository has access to the runner.</>,
      ],
    },
    'Something went wrong': {
      body: <>Something unexpected went wrong.</>,
      remediations: [
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Re-apply this configuration</>,
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>
          <Link inline href="https://support.github.com/">
            Contact GitHub Support
          </Link>{' '}
          if you continue having issues.
        </>,
      ],
    },
    'GHAS not allowed by enterprise': {
      body: (
        <>
          This configuration is enabling GitHub Advanced Security features, but using GitHub Advanced Security is
          restricted by your enterprise policy.
        </>
      ),
      remediations: [
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Contact your enterprise administrators to allow GitHub Advanced Security enablement on this organization.</>,
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Apply a configuration that excludes GitHub Advanced Security.</>,
      ],
    },
    'Secret Protection not allowed by enterprise': {
      body: (
        <>
          This configuration is enabling Secret Protection features, but using Secret Protection is restricted by your
          enterprise policy.
        </>
      ),
      remediations: [
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Contact your enterprise administrators to allow Secret Protection enablement on this organization.</>,
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Apply a configuration that disables Secret Protection.</>,
      ],
    },
    'Code Security not allowed by enterprise': {
      body: (
        <>
          This configuration is enabling Code Security features, but using Code Security is restricted by your
          enterprise policy.
        </>
      ),
      remediations: [
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Contact your enterprise administrators to allow Code Security enablement on this organization.</>,
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Apply a configuration that disables Code Security.</>,
      ],
    },
    'GHAS not purchased': {
      body: (
        <>
          This configuration is enabling GitHub Advanced Security features, but GitHub Advanced Security has not been
          purchased by your organization.
        </>
      ),
      remediations: [
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>
          <Link inline href={docsUrls.ghasTrial}>
            Trial GitHub Advanced Security
          </Link>
          .
        </>,
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Apply a configuration that excludes GitHub Advanced Security.</>,
      ],
    },
    'Secret Protection not purchased': {
      body: (
        <>
          This configuration is enabling Secret Protection features, but Secret Protection has not been purchased by
          your organization.
        </>
      ),
      remediations: [
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Purchase Secret Protection and re-apply this configuration.</>,
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Apply a configuration that disables Secret Protection.</>,
      ],
    },
    'Code Security not purchased': {
      body: (
        <>
          This configuration is enabling Code Security features, but Code Security has not been purchased by your
          organization.
        </>
      ),
      remediations: [
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Purchase Code Security and re-apply this configuration.</>,
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Apply a configuration that disables Code Security.</>,
      ],
    },
    'Automatic dependency submission: Actions disabled': {
      body: (
        <>
          Automatic dependency submission requires actions, but actions is disabled at the
          repository/organization/enterprise level.
        </>
      ),
      remediations: [
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Enable Actions and re-apply this configuration.</>,
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Apply a configuration that delegates automatic dependency setup.</>,
      ],
    },
    'Automatic dependency submission: Labeled runners unavailable': {
      body: (
        <>
          Automatic dependency submission requires that the repository has access to runners with the label
          &apos;dependency-submission&apos;
        </>
      ),
      remediations: [
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Create a runner group with the dependency-submission label.</>,
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Ensure that this repository has been added to the runner group.</>,
        // eslint-disable-next-line @eslint-react/no-missing-key
        <>Apply a configuration that delegates automatic dependency setup.</>,
      ],
    },
  }

  const body = FAILURE_DIALOG_BODY_MAP[title]?.body || FAILURE_DIALOG_BODY_MAP['Something went wrong']?.body
  const remediations =
    FAILURE_DIALOG_BODY_MAP[title]?.remediations || FAILURE_DIALOG_BODY_MAP['Something went wrong']?.remediations || []

  return (
    <Dialog title={title} onClose={() => setShowFailureReasonDialog(false)}>
      <div data-testid="failure-dialog-body">{body}</div>
      <div className={styles.Box}>
        <span className={styles.Text}>Remediation options</span>
        <ul data-testid="failure-dialog-remediations" style={{marginLeft: 20, marginTop: 4}}>
          {remediations.map((remediation, i) => (
            <li key={`remediation${i.toString()}`} style={{marginTop: 4}}>
              {remediation}
            </li>
          ))}
        </ul>
      </div>
    </Dialog>
  )
}

export default FailureReasonDialog

import {Link, Spinner} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {ServerIcon} from '@primer/octicons-react'
import type {Dispatch, SetStateAction} from 'react'
import {useState} from 'react'

import {SummaryCard} from '@github-ui/licensing-common/components/SummaryCard'
import {SummaryCardBanner} from '@github-ui/licensing-common/components/SummaryCardBanner'

import {MeteredEnterpriseServerLicense} from './components/MeteredEnterpriseServerLicense'
import {useExportStatus} from './hooks/use-export-status'
import {ExportJobState} from './types/export-job-state'
import {pluralize} from './utils/text'

import type {Business} from './types/business'
import type {ServerLicense} from './types/server-licenses'

export interface Props {
  business: Business
  isGhasBundled: boolean
  enableGhasBundleMismatchWarning: boolean
  consumedEnterpriseLicenses: number
  isStafftools?: boolean
  serverLicenses: ServerLicense[]
  auditLogQueryUrl?: string
}

const GeneratingLicense = ({consumedEnterpriseLicenses}: {consumedEnterpriseLicenses: number}) => (
  <div className="Box-footer d-flex flex-items-center flex-column border-0 p-5" data-testid="generating-license">
    <Spinner />
    <div className="pt-3">
      Generating a new license for {pluralize(consumedEnterpriseLicenses, 'Enterprise Cloud user')}.
    </div>
  </div>
)

type BannerVariant = 'info' | 'warning' | 'critical' | 'success'

const MESLBanner = ({
  showBanner,
  bannerVariant,
  bannerMessage,
  bannerLink,
  handleCreateLicense,
  setShowBanner,
}: {
  showBanner: boolean
  bannerVariant?: BannerVariant
  bannerMessage?: string
  bannerLink?: string
  handleCreateLicense: () => Promise<void>
  setShowBanner: Dispatch<SetStateAction<boolean>>
}) => {
  if (!bannerMessage || !bannerVariant || !showBanner) return null

  const bannerDescription =
    bannerLink && bannerLink.length > 0 ? (
      <>
        {bannerMessage}{' '}
        <Link href={bannerLink} inline>
          Learn more
        </Link>
      </>
    ) : (
      bannerMessage
    )

  return (
    <SummaryCardBanner
      data-testid="license-status-banner"
      variant={bannerVariant}
      title={bannerVariant}
      description={bannerDescription}
      hideTitle
      primaryAction={
        bannerVariant === 'warning' && (
          <Banner.PrimaryAction onClick={handleCreateLicense}>Generate new license</Banner.PrimaryAction>
        )
      }
      onDismiss={bannerVariant !== 'warning' ? () => setShowBanner(false) : undefined}
    />
  )
}

export function MeteredEnterpriseServerLicenses({
  business,
  consumedEnterpriseLicenses,
  isGhasBundled,
  enableGhasBundleMismatchWarning = false,
  isStafftools = false,
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  serverLicenses: initialServerLicenses = [],
  auditLogQueryUrl = '',
}: Props) {
  let meteredServerLicensesBaseUrl = `/enterprises/${business.slug}/metered_server_licenses`
  if (isStafftools) {
    meteredServerLicensesBaseUrl = `/stafftools${meteredServerLicensesBaseUrl}`
  }

  const activeServerLicense = initialServerLicenses?.[0]
  // setup warning banner if there is a mismatch between the active license seat count and the current GHEC user count
  const activeLicenseSeatCountMismatch = activeServerLicense?.seats !== consumedEnterpriseLicenses

  // setup warning banner if there is a mismatch between the active license GHAS bundle state and the current GHEC account bundle state
  const activeLicenseGhasBundled = !(
    activeServerLicense?.code_security_enabled || activeServerLicense?.secret_protection_enabled
  )

  // A customer who has unbundled GHAS will only benefit from cost savings on GHES if they use an unbundled license (and only on GHES 3.17+),
  // so if their active GHES license is not yet unbundled we prompt them here to regenerate their license.
  // In the event that a customer is rebundled (should be very rare), there is no need to regenerate a new bundled license,
  // as the rebundled customer will still be billed appropriately even if GHES still has an unbundled license.
  const activeLicenseGhasBundleMismatch = enableGhasBundleMismatchWarning
    ? activeLicenseGhasBundled && !isGhasBundled
    : false

  const [serverLicenses, setServerLicenses] = useState(initialServerLicenses)
  const [showBanner, setShowBanner] = useState<boolean>(() =>
    Boolean(activeLicenseSeatCountMismatch || activeLicenseGhasBundleMismatch),
  )
  const [bannerMessage, setBannerMessage] = useState<string>(
    consumedEnterpriseLicenses > 0 && activeLicenseGhasBundleMismatch
      ? 'Your Advanced Security license has been unbundled into separate SKUs. Generate a new license to update your Enterprise Server usage.'
      : consumedEnterpriseLicenses > 0 && activeLicenseSeatCountMismatch
        ? 'Your license usage for Enterprise Cloud has changed. Generate a new license key to update server seats.'
        : '',
  )
  const [bannerLink, setBannerLink] = useState<string>(
    consumedEnterpriseLicenses > 0 && activeLicenseGhasBundleMismatch
      ? 'https://docs.github.com/enterprise-cloud@latest/billing/managing-billing-for-your-products/managing-billing-for-github-advanced-security/migrating-from-ghas-to-cs-and-sp'
      : '',
  )

  const [bannerVariant, setBannerVariant] = useState<BannerVariant | undefined>(
    activeLicenseSeatCountMismatch || activeLicenseGhasBundleMismatch ? 'warning' : undefined,
  )
  const [isGenerating, setIsGenerating] = useState<boolean>(false)
  const {exportJobState, startExport} = useExportStatus(meteredServerLicensesBaseUrl)

  const showAuditLogLink = isStafftools && auditLogQueryUrl.length > 0

  async function handleCreateLicense() {
    setIsGenerating(true)

    const response = await startExport()
    if (exportJobState === ExportJobState.Error || !response) {
      setBannerVariant('critical')
      setBannerMessage('There was an error generating a new server license. Please try again later.')
      setBannerLink('')
      setShowBanner(true)
      setIsGenerating(false)
      return
    }

    setBannerVariant('success')
    setBannerMessage(
      `New server license generated for ${pluralize(
        consumedEnterpriseLicenses,
        'Enterprise Cloud user',
      )}. Upload to your server instance.`,
    )
    setBannerLink('')
    setShowBanner(true)

    setServerLicenses([response?.license, ...serverLicenses])
    setIsGenerating(false)
  }

  return (
    <div className="mb-4" data-testid="metered-enterprise-server-licenses">
      <SummaryCard
        headerIconComponent={ServerIcon}
        title="Enterprise Server licenses"
        headerMenu={showAuditLogLink && <Link href={auditLogQueryUrl}>Audit Log</Link>}
      >
        {isGenerating ? (
          <GeneratingLicense consumedEnterpriseLicenses={consumedEnterpriseLicenses} />
        ) : (
          <DisplayLicenses
            serverLicenses={serverLicenses}
            bannerVariant={bannerVariant}
            showBanner={showBanner}
            bannerMessage={bannerMessage}
            bannerLink={bannerLink}
            handleCreateLicense={handleCreateLicense}
            setShowBanner={setShowBanner}
            consumedEnterpriseLicenses={consumedEnterpriseLicenses}
            meteredServerLicensesBaseUrl={meteredServerLicensesBaseUrl}
          />
        )}
      </SummaryCard>
    </div>
  )
}

const DisplayLicenses = ({
  serverLicenses,
  bannerVariant,
  showBanner,
  bannerMessage,
  bannerLink,
  handleCreateLicense,
  setShowBanner,
  consumedEnterpriseLicenses,
  meteredServerLicensesBaseUrl,
}: {
  serverLicenses: ServerLicense[]

  bannerVariant?: BannerVariant
  showBanner: boolean
  bannerMessage?: string
  bannerLink?: string
  handleCreateLicense: () => Promise<void>
  setShowBanner: Dispatch<SetStateAction<boolean>>
  consumedEnterpriseLicenses: number

  meteredServerLicensesBaseUrl: string
}) => {
  if (serverLicenses.length === 0) {
    return (
      <>
        {bannerVariant === 'critical' && (
          <MESLBanner
            showBanner={showBanner}
            bannerVariant={bannerVariant}
            bannerMessage={bannerMessage}
            bannerLink={bannerLink}
            handleCreateLicense={handleCreateLicense}
            setShowBanner={setShowBanner}
          />
        )}
        <div className="Box-footer d-flex flex-items-center flex-justify-between border-0">
          <div className="text-normal ml-1 pl-6 color-fg-default">
            You don&apos;t have any server licenses.&nbsp;
            {consumedEnterpriseLicenses ? (
              <Link className="Link--inTextBlock cursor-pointer" inline onClick={handleCreateLicense}>
                Generate new license
              </Link>
            ) : (
              <span data-testid="add-cloud-users-message">
                Please add users to your Enterprise Cloud account to generate a license
              </span>
            )}
            .
          </div>
        </div>
      </>
    )
  }

  return (
    <>
      <MESLBanner
        showBanner={showBanner}
        bannerVariant={bannerVariant}
        bannerMessage={bannerMessage}
        bannerLink={bannerLink}
        handleCreateLicense={handleCreateLicense}
        setShowBanner={setShowBanner}
      />
      {serverLicenses.map((serverLicense, i) => (
        <MeteredEnterpriseServerLicense
          key={serverLicense.reference_number}
          serverLicense={serverLicense}
          // Only show the download link for the first license
          showDownloadLink={i === 0}
          meteredServerLicensesBaseUrl={meteredServerLicensesBaseUrl}
        />
      ))}
    </>
  )
}

import {verifiedFetch} from '@github-ui/verified-fetch'
import {Box, Button, Flash, IconButton, Link, Spinner, Text} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {AlertIcon, CheckIcon, InfoIcon, ServerIcon, StopIcon, XIcon} from '@primer/octicons-react'
import type {Icon} from '@primer/octicons-react'
import type {Dispatch, SetStateAction} from 'react'
import {useState} from 'react'

import {MeteredEnterpriseServerLicense} from './components/MeteredEnterpriseServerLicense'
import type {ServerLicense} from './types/server-licenses'
import type {Business} from './types/business'
import {pluralize} from './utils/text'

export interface Props {
  business: Business
  consumedEnterpriseLicenses: number
  isStafftools?: boolean
  serverLicenses: ServerLicense[]
  auditLogQueryUrl?: string
}

const GeneratingLicense = ({consumedEnterpriseLicenses}: {consumedEnterpriseLicenses: number}) => (
  <Box
    className="Box-footer"
    sx={{display: 'flex', border: 0, alignItems: 'center', flexDirection: 'column', padding: '32px'}}
    data-testid="generating-license"
  >
    <Spinner />
    <Text as="div" sx={{paddingTop: '16px'}}>
      Generating a new license for {pluralize(consumedEnterpriseLicenses, 'Enterprise Cloud user')}.
    </Text>
  </Box>
)

type BannerVariant = 'default' | 'warning' | 'danger' | 'success'

const Banner = ({
  showBanner,
  bannerVariant,
  bannerMessage,
  handleCreateLicense,
  setShowBanner,
}: {
  showBanner: boolean
  bannerVariant?: BannerVariant
  bannerMessage?: string
  handleCreateLicense: () => Promise<void>
  setShowBanner: Dispatch<SetStateAction<boolean>>
}) => {
  if (!bannerMessage || !bannerVariant || !showBanner) return null

  let BannerIcon: Icon
  switch (bannerVariant) {
    case 'warning':
      BannerIcon = AlertIcon
      break
    case 'success':
      BannerIcon = CheckIcon
      break
    case 'danger':
      BannerIcon = StopIcon
      break
    default:
      BannerIcon = InfoIcon
      break
  }

  return (
    <Flash
      data-testid="license-status-banner"
      variant={bannerVariant}
      sx={{
        display: 'flex',
        alignItems: 'center',
        borderRadius: '0',
        borderTop: '0',
        borderLeft: '0',
        borderRight: '0',
      }}
    >
      {BannerIcon && <Octicon aria-label="Alert icon" icon={BannerIcon} />}
      <span className="flex-1 pl-3">{bannerMessage}</span>
      {bannerVariant === 'warning' ? (
        <Button
          aria-label="Generate new license"
          onClick={() => handleCreateLicense()}
          sx={{svg: {color: 'black', margin: 0}}}
        >
          Generate new license
        </Button>
      ) : (
        // eslint-disable-next-line primer-react/a11y-remove-disable-tooltip
        <IconButton
          unsafeDisableTooltip
          variant="invisible"
          aria-label="Close"
          icon={XIcon}
          onClick={() => setShowBanner(false)}
          size="small"
          sx={{svg: {color: 'black', margin: 0}}}
        />
      )}
    </Flash>
  )
}

export function MeteredEnterpriseServerLicenses({
  business,
  consumedEnterpriseLicenses,
  isStafftools = false,
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  serverLicenses: initialServerLicenses = [],
  auditLogQueryUrl = '',
}: Props) {
  const meteredServerLicensesBaseUrl = isStafftools
    ? `/stafftools/enterprises/${business.slug}/metered_server_licenses`
    : `/enterprises/${business.slug}/metered_server_licenses`

  const activeServerLicense = initialServerLicenses?.[0]
  // setup warning banner if there is a mismatch between the active license seat count and the current GHEC user count
  const activeLicenseSeatCountMismatch = activeServerLicense?.seats !== consumedEnterpriseLicenses

  const [serverLicenses, setServerLicenses] = useState(initialServerLicenses)
  const [showBanner, setShowBanner] = useState<boolean>(() => Boolean(activeLicenseSeatCountMismatch))
  const [bannerMessage, setBannerMessage] = useState<string>(
    consumedEnterpriseLicenses > 0 && activeLicenseSeatCountMismatch
      ? 'Your license usage for Enterprise Cloud has changed. Generate a new license key to update server seats.'
      : '',
  )
  const [bannerVariant, setBannerVariant] = useState<BannerVariant | undefined>(
    activeLicenseSeatCountMismatch ? 'warning' : undefined,
  )
  const [isGenerating, setIsGenerating] = useState<boolean>(false)

  const showAuditLogLink = isStafftools && auditLogQueryUrl.length > 0

  async function handleCreateLicense() {
    setIsGenerating(true)
    const response = await verifiedFetch(meteredServerLicensesBaseUrl, {method: 'POST'})

    if (!response.ok) {
      setBannerVariant('danger')
      setBannerMessage('There was an error generating a new server license. Please try again later.')
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
    setShowBanner(true)

    const serverLicense: ServerLicense = await response.json()
    setServerLicenses([serverLicense, ...serverLicenses])
    setIsGenerating(false)

    // automatically download the generated license in a new tab (browsers will typically open/close this quickly)
    const downloadLink = `${meteredServerLicensesBaseUrl}/${serverLicense.reference_number}`
    window?.open(downloadLink, '_blank')?.focus()
  }

  return (
    <div className="Box mb-4 rounded-2">
      <div className="Box-header d-flex flex-row flex-items-center gap-2">
        <div className="p-2 bgColor-default border rounded-2">
          <Octicon icon={ServerIcon} className="d-block" size={16} />
        </div>
        <div className="flex-1 d-flex flex-row flex-items-center gap-2">
          <h3 className="text-normal">Enterprise Server licenses</h3>
        </div>
        {showAuditLogLink && <Link href={auditLogQueryUrl}>Audit Log</Link>}
      </div>
      {isGenerating ? (
        <GeneratingLicense consumedEnterpriseLicenses={consumedEnterpriseLicenses} />
      ) : (
        <DisplayLicenses
          serverLicenses={serverLicenses}
          bannerVariant={bannerVariant}
          showBanner={showBanner}
          bannerMessage={bannerMessage}
          handleCreateLicense={handleCreateLicense}
          setShowBanner={setShowBanner}
          consumedEnterpriseLicenses={consumedEnterpriseLicenses}
          meteredServerLicensesBaseUrl={meteredServerLicensesBaseUrl}
        />
      )}
    </div>
  )
}

const DisplayLicenses = ({
  serverLicenses,
  bannerVariant,
  showBanner,
  bannerMessage,
  handleCreateLicense,
  setShowBanner,
  consumedEnterpriseLicenses,
  meteredServerLicensesBaseUrl,
}: {
  serverLicenses: ServerLicense[]

  bannerVariant?: BannerVariant
  showBanner: boolean
  bannerMessage?: string
  handleCreateLicense: () => Promise<void>
  setShowBanner: Dispatch<SetStateAction<boolean>>
  consumedEnterpriseLicenses: number

  meteredServerLicensesBaseUrl: string
}) => {
  if (serverLicenses.length === 0) {
    return (
      <>
        {bannerVariant === 'danger' && (
          <Banner
            showBanner={showBanner}
            bannerVariant={bannerVariant}
            bannerMessage={bannerMessage}
            handleCreateLicense={handleCreateLicense}
            setShowBanner={setShowBanner}
          />
        )}
        <div className="Box-footer d-flex flex-items-center border-0">
          <div className="text-normal ml-1 pl-6">
            You don&apos;t have any server licenses.&nbsp;
            {consumedEnterpriseLicenses ? (
              <Link inline sx={{cursor: 'pointer'}} onClick={handleCreateLicense}>
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
      <Banner
        showBanner={showBanner}
        bannerVariant={bannerVariant}
        bannerMessage={bannerMessage}
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

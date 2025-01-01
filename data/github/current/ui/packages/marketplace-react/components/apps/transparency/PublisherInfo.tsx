import {GitHubAvatar} from '@github-ui/github-avatar'
import {Link} from '@primer/react'
import {TransparencyDataTable} from './TransparencyDataTable'
import type {AppListing} from '@github-ui/marketplace-common'

export type PublisherInfoProps = {
  app: AppListing
}

export function PublisherInfo({app}: PublisherInfoProps) {
  const {
    ownerSafeProfileName,
    ownerImage,
    ownerType,
    traderAddress,
    businessId,
    euTrader,
    statusUrl,
    tosUrl,
    privacyPolicyUrl,
    supportUrl,
    supportEmail,
    publisher2faRequired,
    verifiedProfileDomains,
  } = app

  const items = [
    {
      label: 'Developer',
      value: ownerSafeProfileName && (
        <div className="d-flex flex-items-center gap-2">
          {ownerImage && (
            <GitHubAvatar
              src={ownerImage}
              alt={ownerSafeProfileName}
              size={16}
              square={ownerType === 'User' ? false : true}
            />
          )}
          {ownerSafeProfileName}
        </div>
      ),
    },
    {
      label: 'Company domain',
      value: verifiedProfileDomains.length > 0 && (
        <>
          {verifiedProfileDomains.map(domain => (
            <Link key={domain} href={`https://${domain}`} rel="nofollow" className="d-block">
              {domain}
            </Link>
          ))}
        </>
      ),
    },
    {label: 'Business address', value: traderAddress && <>{traderAddress}</>},
    {
      label: 'Business ID',
      value: businessId && <>{businessId}</>,
    },
    {
      label: 'EU Trader',
      value: euTrader && <>{euTrader}</>,
    },
    {
      label: 'Status page',
      value: statusUrl && (
        <Link href={statusUrl} rel="nofollow">
          {statusUrl}
        </Link>
      ),
    },
    {
      label: 'Terms of service',
      value: tosUrl && (
        <Link href={tosUrl} rel="nofollow">
          {tosUrl}
        </Link>
      ),
    },
    {
      label: 'Privacy policy',
      value: privacyPolicyUrl && (
        <Link href={privacyPolicyUrl} rel="nofollow">
          {privacyPolicyUrl}
        </Link>
      ),
    },
    {
      label: 'Support URL',
      value: supportUrl && (
        <Link href={supportUrl} rel="nofollow">
          {supportUrl}
        </Link>
      ),
    },
    {
      label: 'Support email',
      value: supportEmail && <Link href={`mailto:${supportEmail}`}>{supportEmail}</Link>,
    },
    {
      label: 'Publisher 2FA Required',
      value: publisher2faRequired && <>{publisher2faRequired}</>,
    },
  ]

  return (
    <div data-testid="publisher-info">
      <TransparencyDataTable items={items} />
    </div>
  )
}

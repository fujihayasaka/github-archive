import type {LicenseHolder} from './types'
import {useCallback, useEffect, useState} from 'react'
import {Link} from '@primer/react'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {Dialog} from '@primer/react/experimental'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {AlertIcon} from '@primer/octicons-react'
import {useCustomerId} from './CustomerIdContext'
import {useProduct} from './ProductContext'

export interface LicensifyLicenseDetailsProps {
  licenseHolder: LicenseHolder
  onClose: () => void
}

const LoadingState = {
  Loading: 'Loading',
  Loaded: 'Loaded',
  Error: 'Error',
} as const

type LoadingState = (typeof LoadingState)[keyof typeof LoadingState]

export function LicenseDetails({licenseHolder, onClose}: LicensifyLicenseDetailsProps) {
  const customerId = useCustomerId()
  const product = useProduct()
  const {type, id} = licenseHolder

  const [state, setState] = useState<LoadingState>(LoadingState.Loading)
  const [licenseDetails, setLicenseDetails] = useState([])

  const fetchLicenseDetails = useCallback(async () => {
    setState(LoadingState.Loading)
    const response = await verifiedFetchJSON(
      `/stafftools/customers/${customerId}/licensify_licenses/${type}/${id}/${product}`,
    )

    if (response.ok) {
      const data = await response.json()
      setState(LoadingState.Loaded)
      setLicenseDetails(data || [])
    } else {
      setState(LoadingState.Error)
    }
  }, [customerId, id, type, product])

  useEffect(() => {
    fetchLicenseDetails()
  }, [fetchLicenseDetails])

  const dialogbody = useCallback(() => {
    if (state === LoadingState.Loading) {
      return <LoadingSkeleton />
    } else if (state === LoadingState.Error) {
      return (
        <div>
          <AlertIcon className="blankslate-icon fgColor-attention" />
          <span>There was an error loading license details </span>
          <Link onClick={fetchLicenseDetails}>Try again</Link>
        </div>
      )
    } else {
      return <pre>{JSON.stringify(licenseDetails, null, 2)}</pre>
    }
  }, [fetchLicenseDetails, licenseDetails, state])

  return (
    <Dialog onClose={onClose} title={`License details for ${licenseHolder.display_name}`}>
      {dialogbody()}
    </Dialog>
  )
}

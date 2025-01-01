import {useState} from 'react'
import {STAFFTOOLS_RECONCILE_ORG_TRANSFER_USAGES_ROUTE} from '../../routes'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {Button, FormControl, Heading, TextInput} from '@primer/react'

const ReconcileOrgTransferUsagesRoutePage = () => {
  const [organizationId, setOrganizationId] = useState('')
  const [sourceEnterpriseCustomerId, setSourceEnterpriseCustomerId] = useState('')
  const [destinationEnterpriseCustomerId, setDestinationEnterpriseCustomerId] = useState('')

  const [status, setStatus] = useState<'idle' | 'success' | 'error'>('idle')
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

  interface FormValues {
    organizationId: string
    sourceEnterpriseCustomerId: string
    destinationEnterpriseCustomerId: string
  }

  const handleSubmit = async () => {
    setStatus('idle')
    setErrorMessage(null)
    try {
      const payload: FormValues = {organizationId, sourceEnterpriseCustomerId, destinationEnterpriseCustomerId}
      const response = await verifiedFetchJSON(STAFFTOOLS_RECONCILE_ORG_TRANSFER_USAGES_ROUTE.fullPath, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: payload,
      })

      if (response.status === 422) {
        setStatus('error')
        const data = await response.json()
        setErrorMessage(data.error || 'Invalid request. Please verify your input and try again.')
        return
      }

      if (!response.ok) {
        setStatus('error')
        const data = await response.json()
        setErrorMessage(data.error || 'Submission failed. Please try again.')
        return
      }

      setStatus('success')
    } catch {
      setStatus('error')
      setErrorMessage('Submission failed. Please try again.')
    }
  }

  return (
    <>
      <div>
        <Heading as="h1">Reconcile Org Transfer Usages</Heading>
        {status === 'success' && (
          <div>
            <p>Usages reconciled successfully!</p>
          </div>
        )}
        {status === 'error' && errorMessage && (
          <div>
            <p>Error: {errorMessage}</p>
          </div>
        )}
        <FormControl>
          <FormControl.Label>Source Enterprise Customer Id</FormControl.Label>
          <TextInput
            name="source_enterprise_customer_id"
            value={sourceEnterpriseCustomerId}
            onChange={e => setSourceEnterpriseCustomerId(e.target.value)}
          />
        </FormControl>
        <FormControl>
          <FormControl.Label>Organization Id</FormControl.Label>
          <TextInput name="organization_id" value={organizationId} onChange={e => setOrganizationId(e.target.value)} />
        </FormControl>
        <FormControl>
          <FormControl.Label>Destination Enterprise Customer Id</FormControl.Label>
          <TextInput
            name="destination_enterprise_customer_id"
            value={destinationEnterpriseCustomerId}
            onChange={e => setDestinationEnterpriseCustomerId(e.target.value)}
          />
        </FormControl>
        <Button onClick={handleSubmit}>Submit</Button>
      </div>
    </>
  )
}

export default ReconcileOrgTransferUsagesRoutePage

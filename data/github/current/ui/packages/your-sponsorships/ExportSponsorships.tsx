import {useRef, useState} from 'react'
import {Button, Link, Spinner} from '@primer/react'
import {Dialog} from '@primer/react/deprecated'
import {MoveToBottomIcon} from '@primer/octicons-react'
import {testIdProps} from '@github-ui/test-id-props'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {TabStates} from './your-sponsorships-types'

import styles from './ExportSponsorships.module.css'

interface ExportSponsorshipProps {
  sponsorLogin: string
  viewerPrimaryEmail?: string
  currentTab: TabStates
  setFlash: (props: {variant: 'success' | 'danger'; message: string}) => void
}

export const ExportSponsorships = ({
  sponsorLogin,
  viewerPrimaryEmail,
  currentTab,
  setFlash,
}: ExportSponsorshipProps) => {
  const [isOpen, setIsOpen] = useState(false)
  const [isLoading, setIsLoading] = useState(false)
  const returnFocusRef = useRef(null)

  const onClick = async () => {
    setIsLoading(true)
    const resp = await verifiedFetchJSON(`/orgs/${sponsorLogin}/sponsoring/sponsorships_exports`, {
      method: 'POST',
      body: {active: currentTab === TabStates.ACTIVE_SPONSORSHIPS},
    })

    if (!resp.ok) {
      setIsLoading(false)
      setIsOpen(false)
      setFlash({variant: 'danger', message: 'There was a problem exporting your sponsorships.'})
      return
    }

    const jsonResp = await resp.json()
    setIsLoading(false)
    setIsOpen(false)
    setFlash({variant: 'success', message: jsonResp.msg})
  }

  return (
    <>
      <Button
        ref={returnFocusRef}
        leadingVisual={MoveToBottomIcon}
        onClick={() => {
          setIsOpen(true)
        }}
        {...testIdProps('your-sponsorships-export-button')}
      >
        Export as CSV
      </Button>
      <Dialog
        returnFocusRef={returnFocusRef}
        title="Export sponsorships"
        isOpen={isOpen}
        onDismiss={() => {
          setIsOpen(false)
        }}
      >
        <div>
          <Dialog.Header id="header">Export sponsorships</Dialog.Header>
          <div className={styles.Box}>
            <span>
              We&apos;ll start the export process and email you at{' '}
              <span className={styles.Text}>{viewerPrimaryEmail}</span> with the export attached when it&apos;s done.
              Update your{' '}
              <Link inline href="/settings/emails">
                contact email settings
              </Link>{' '}
              to change where the file is sent.
            </span>
            <Button
              block
              variant="primary"
              onClick={onClick}
              className={styles.Button}
              {...testIdProps('your-sponsorships-start-export-button')}
            >
              {isLoading ? <Spinner size="small" /> : 'Start export'}
            </Button>
          </div>
        </div>
      </Dialog>
    </>
  )
}

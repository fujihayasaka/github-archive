import {useRef, useState} from 'react'
import {Button, Link, Spinner} from '@primer/react'
import {Dialog} from '@primer/react/deprecated'
import {MoveToBottomIcon} from '@primer/octicons-react'
import {testIdProps} from '@github-ui/test-id-props'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

import styles from './ExportDependencies.module.css'

export const BannerVariants = {
  SUCCESS: 'success',
  ERROR: 'critical',
} as const

export type BannerVariants = (typeof BannerVariants)[keyof typeof BannerVariants]

interface ExportDependenciesProps {
  orgName: string
  viewerPrimaryEmail?: string
  setBanner: (props: {
    variant: typeof BannerVariants.SUCCESS | typeof BannerVariants.ERROR
    message: string
    isVisible: boolean
  }) => void
}

export const ExportDependencies = ({orgName, setBanner, viewerPrimaryEmail}: ExportDependenciesProps) => {
  const [isExportModalOpen, setIsExportModalOpen] = useState(false)
  const [isLoading, setIsLoading] = useState(false)
  const returnFocusRef = useRef(null)

  const onClick = async () => {
    setIsLoading(true)
    try {
      const resp = await verifiedFetchJSON(`/orgs/${orgName}/sponsoring/sponsorships_dependencies_exports`, {
        method: 'POST',
        body: {},
      })

      if (!resp.ok) {
        setIsLoading(false)
        setIsExportModalOpen(false)
        setBanner({
          variant: BannerVariants.ERROR,
          message: 'There was a problem exporting your dependencies.',
          isVisible: true,
        })
        return
      }
      const jsonResp = await resp.json()
      setIsLoading(false)
      setIsExportModalOpen(false)
      setBanner({
        variant: BannerVariants.SUCCESS,
        message: jsonResp.msg,
        isVisible: true,
      })
      return
    } catch {
      setIsLoading(false)
      setIsExportModalOpen(false)
      setBanner({
        variant: BannerVariants.ERROR,
        message: 'There was a problem exporting your dependencies.',
        isVisible: true,
      })
      return
    }
  }

  return (
    <>
      <Button
        ref={returnFocusRef}
        leadingVisual={MoveToBottomIcon}
        onClick={() => {
          setIsExportModalOpen(true)
        }}
        {...testIdProps('dependencies-export-button')}
      >
        Export as CSV
      </Button>
      <Dialog
        returnFocusRef={returnFocusRef}
        title="Export dependencies"
        isOpen={isExportModalOpen}
        onDismiss={() => {
          setIsExportModalOpen(false)
        }}
      >
        <div>
          <Dialog.Header id="header">Export dependencies</Dialog.Header>
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
              {...testIdProps('dependencies-start-export-button')}
            >
              {isLoading ? <Spinner size="small" /> : 'Start export'}
            </Button>
          </div>
        </div>
      </Dialog>
    </>
  )
}

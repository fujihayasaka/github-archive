import type {PropsWithChildren} from 'react'
import {useState} from 'react'
import {Button} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {useClickAnalytics} from '@github-ui/use-analytics'

import {clsx} from 'clsx'
import styles from './DialogCard.module.css'

export interface DialogCardProps {
  title: string
  username: string
  stat?: string
  delimiter?: string
  description: string
  isOpen: boolean
  total_contributors_requests: string
}

export function DialogCard({
  children,
  username,
  title,
  stat,
  description,
  delimiter,
  isOpen,
  total_contributors_requests,
  ...props
}: PropsWithChildren<DialogCardProps>) {
  const {sendClickAnalyticsEvent} = useClickAnalytics()
  const [isDialogOpen, setIsDialogOpen] = useState(isOpen)

  const openDialog = () => {
    sendClickAnalyticsEvent({
      category: 'api_insights',
      action: 'click_view_all_contributors',
      label: 'ref_cta:view_all_contributors',
    })
    setIsDialogOpen(true)
  }

  const closeDialog = () => {
    setIsDialogOpen(false)
  }

  return (
    <div className="border rounded-2 p-3 d-flex flex-column flex-1 gap-1" {...props}>
      <div className="d-flex flex-row">
        <p className="h5 m-0">{title}</p>
        <Button variant="invisible" className="f6 ml-auto" onClick={openDialog}>
          View all contributors
        </Button>
        {isDialogOpen && (
          <Dialog
            title="User request limit contributors"
            width="xlarge"
            subtitle={`All contributors to @${username}'s request limit`}
            onClose={closeDialog}
            footerButtons={[
              {
                buttonType: 'default',
                content: 'Close',
                onClick: () => {
                  closeDialog()
                },
              },
            ]}
            renderFooter={() => {
              return (
                <Dialog.Footer>
                  {total_contributors_requests !== '0' && (
                    <div className="d-flex justify-content-between width-full">
                      <span className="f6 fgColor-muted d-inline-flex flex-content-start flex-content-align-center px-1 width-full">
                        Total
                      </span>
                      <span className="f5 text-bold fgColor-default d-inline-flex flex-content-end px-1 mr-3">
                        {total_contributors_requests}
                      </span>
                    </div>
                  )}
                  <div>
                    <Button
                      variant="default"
                      onClick={() => {
                        closeDialog()
                      }}
                    >
                      Close
                    </Button>
                  </div>
                </Dialog.Footer>
              )
            }}
          >
            {children}
          </Dialog>
        )}
      </div>
      <p className={clsx(styles.dialogCardRate, 'f2 m-0')}>
        {stat}
        {!stat && 'N/A'}
        {stat && delimiter && <span className="f3"> / {delimiter}</span>}
      </p>
      <p className="m-0 fgColor-muted f6">{description}</p>
    </div>
  )
}

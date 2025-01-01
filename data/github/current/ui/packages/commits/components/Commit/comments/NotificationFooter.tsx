import {useCurrentRepository} from '@github-ui/current-repository'
import {useCSRFToken} from '@github-ui/use-csrf-token'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {BellIcon, BellSlashIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {forwardRef, useState} from 'react'

type NotificationFooterProps = {
  commitOid: string
  subscribed: boolean
}

export const NotificationsFooter = forwardRef<HTMLDivElement, NotificationFooterProps>(
  ({commitOid, subscribed}, ref) => {
    const [subscribeState, setSubscribeState] = useState(subscribed)
    const [updated, setUpdated] = useState(false)
    const repo = useCurrentRepository()
    const token = useCSRFToken('/notifications/thread', 'post')

    let descriptionText

    if (updated) {
      descriptionText = `You're now ${subscribeState ? 'subscribed' : 'unsubscribed'} to this thread.`
    } else {
      if (subscribeState) {
        descriptionText = "You're receiving notifications because you're subscribed to this thread."
      } else {
        descriptionText = "You're not receiving notifications from this thread."
      }
    }

    const updateSubscription = async () => {
      const formData = new FormData()
      formData.append('repository_id', repo.id.toString())
      formData.append('thread_id', commitOid)
      formData.append('thread_class', 'Commit')
      formData.append('id', subscribeState ? 'unsubscribe' : 'subscribe')
      // eslint-disable-next-line github/authenticity-token
      formData.append('authenticity_token', token ?? '')

      const response = await verifiedFetch('/notifications/thread', {
        method: 'POST',
        body: formData,
      })

      if (response.ok) {
        setSubscribeState(!subscribeState)
        setUpdated(true)
      }
    }

    return (
      <div className="d-flex flex-items-center border rounded-2 p-2 gap-2" ref={ref}>
        <Button onClick={updateSubscription} size="small" leadingVisual={subscribeState ? BellSlashIcon : BellIcon}>
          {subscribeState ? 'Unsubscribe' : 'Subscribe'}
        </Button>
        <p role="status" className="f6 fgColor-muted mb-0">
          {descriptionText}
        </p>
      </div>
    )
  },
)

NotificationsFooter.displayName = 'NotificationsFooter'

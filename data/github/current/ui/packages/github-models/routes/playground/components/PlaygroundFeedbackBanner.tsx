import {Link, useResponsiveValue} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {sendStats} from '@github-ui/stats'
import {useEffect} from 'react'
import {bookACallUrl, feedbackUrl} from '../../../constants'

export function PlaygroundFeedbackBanner() {
  const isMobile = useResponsiveValue({narrow: true}, false)

  useEffect(() => {
    sendStats({
      incrementKey: 'MODELS_PLAYGROUND_FEEDBACK_BANNER_DISPLAYED',
    })
  }, [])

  const bookCall = () => {
    sendStats({
      incrementKey: 'MODELS_PLAYGROUND_FEEDBACK_BANNER_BOOK_CALL_SELECTED',
    })
  }

  const shareFeedback = () => {
    sendStats({
      incrementKey: 'MODELS_PLAYGROUND_FEEDBACK_BANNER_SHARE_FEEDBACK_SELECTED',
    })
  }

  return (
    <Banner className={isMobile ? 'rounded-2 mb-2' : 'rounded-0'} title="Talk to us" hideTitle>
      <Banner.Description>
        Got feedback?&nbsp;
        <Link inline onClick={bookCall} href={bookACallUrl} className="cursor-pointer">
          Book a call
        </Link>
        &nbsp;or&nbsp;
        <Link inline onClick={shareFeedback} href={feedbackUrl} className="cursor-pointer">
          share feedback via discussion
        </Link>
        .
      </Banner.Description>
    </Banner>
  )
}

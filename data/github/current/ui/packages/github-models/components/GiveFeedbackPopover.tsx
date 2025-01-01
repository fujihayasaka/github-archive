import {Button, IconButton, Link, Popover} from '@primer/react'
import {XIcon} from '@primer/octicons-react'
import styles from './GiveFeedbackPopover.module.css'
import {useEffect} from 'react'
import {sendStats} from '@github-ui/stats'
import {bookACallUrl, feedbackUrl} from '../constants'

export function GiveFeedbackPopover({handleClose, mobile}: {handleClose: () => void; mobile?: boolean}) {
  useEffect(() => {
    sendStats({
      incrementKey: 'MODELS_PLAYGROUND_FEEDBACK_POPOVER_DISPLAYED',
    })
  }, [])

  const bookCall = () => {
    sendStats({
      incrementKey: 'MODELS_PLAYGROUND_FEEDBACK_POPOVER_BOOK_CALL_SELECTED',
    })
  }

  const shareFeedback = () => {
    sendStats({
      incrementKey: 'MODELS_PLAYGROUND_FEEDBACK_POPOVER_SHARE_FEEDBACK_SELECTED',
    })
  }

  return (
    <Popover open caret={mobile ? 'top-right' : 'top'} className={mobile ? 'right-0' : ''}>
      <Popover.Content className={styles.feedbackPopover}>
        <div className="d-flex flex-justify-end flex-items-center position-absolute top-0 right-0 p-2">
          <IconButton size="small" variant="invisible" icon={XIcon} aria-label="Close" onClick={handleClose} />
        </div>
        <span className="text-bold">Welcome to GitHub Models!</span>
        <p>
          We want to make Models Playground amazing for you. Got feedback? Book a call or&nbsp;
          <Link inline href={feedbackUrl} onClick={shareFeedback} className="cursor-pointer">
            share feedback via discussion
          </Link>
          .
        </p>
        <div className="d-flex">
          <Button as="a" href={bookACallUrl} onClick={bookCall}>
            Book a call
          </Button>
        </div>
      </Popover.Content>
    </Popover>
  )
}

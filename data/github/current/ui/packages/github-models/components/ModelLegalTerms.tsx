import {testIdProps} from '@github-ui/test-id-props'
import {Link} from '@primer/react'
import {useRef, useState} from 'react'
import {FeedbackDialog} from './FeedbackDialog'
import {useNavigate} from '@github-ui/use-navigate'
import {useLocation} from 'react-router-dom'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {ShowModelPayload} from '../types'
import styles from './ModelLegalTerms.module.css'
import {productTermsLink, privacyStatementLink} from '../constants'

export const ModelLegalTerms = ({modelName}: {modelName: string}) => {
  const {isLoggedIn} = useRoutePayload<ShowModelPayload>()
  const [isFeedbackDialogOpen, setIsFeedbackDialogOpen] = useState(false)
  const returnFocusRef = useRef(null)
  const navigate = useNavigate()
  const currentUrl = useLocation().pathname
  const handleClick = () => {
    if (isLoggedIn) {
      setIsFeedbackDialogOpen(true)
    } else {
      navigate(`/login?return_to=${encodeURIComponent(currentUrl)}`)
    }
  }
  return (
    <>
      <span className={styles.linkContainer} {...testIdProps('legal-terms')}>
        Azure hosted. AI powered, can make mistakes.{' '}
        <Link as="button" ref={returnFocusRef} onClick={handleClick} inline muted>
          Share feedback
        </Link>
        . Subject to{' '}
        <Link href={productTermsLink} inline muted tabIndex={0}>
          Product Terms
        </Link>{' '}
        &{' '}
        <Link href={privacyStatementLink} inline muted tabIndex={0}>
          Privacy Statement
        </Link>
        . Not intended for production/sensitive data.
      </span>
      {isFeedbackDialogOpen && (
        <FeedbackDialog
          returnFocusRef={returnFocusRef}
          isFeedbackDialogOpen={isFeedbackDialogOpen}
          setIsFeedbackDialogOpen={setIsFeedbackDialogOpen}
          modelName={modelName}
        />
      )}
    </>
  )
}

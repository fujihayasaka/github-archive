import {CheckIcon} from '@primer/octicons-react'
import {Link} from '@primer/react'

import {clsx} from 'clsx'
import styles from './Summary.module.css'

export interface Props {
  copilotTocLink: string
  cfbHelpLink: string
  cfeHelpLink: string
}

export function EnableCTA({copilotTocLink, cfbHelpLink, cfeHelpLink}: Props) {
  return (
    <div className="Box-body p-4 d-flex flex-column" data-testid="enable-copilot-cta">
      <div className={clsx('d-flex', 'flex-md-row', 'flex-column', styles.gap6)}>
        <div className="flex-1">
          <div className="h4">Copilot Business</div>
          <div>
            <p className="text-small text-bold my-2">What&apos;s included</p>
            <ul className="list-style-none">
              <li className="fgColor-muted mb-2">
                <CheckIcon className="fgColor-success" /> Code completions and chat in IDE
              </li>
              <li className="fgColor-muted mb-2">
                <CheckIcon className="fgColor-success" /> Security vulnerability filter
              </li>
              <li className="fgColor-muted mb-2">
                <CheckIcon className="fgColor-success" /> Code referencing
              </li>
              <li className="fgColor-muted mb-2">
                <CheckIcon className="fgColor-success" /> CLI assistance
              </li>
            </ul>
          </div>
          <Link href={cfbHelpLink}>Learn more about Copilot Business</Link>
        </div>
        <div className="flex-1">
          <div className="h4">Copilot Enterprise</div>
          <div>
            <p className="text-small text-bold my-2">Everything in Copilot Business plus...</p>
            <ul className="list-style-none">
              <li className="fgColor-muted mb-2">
                <CheckIcon className="fgColor-success" /> Copilot in the entire GitHub Platform
              </li>
              <li className="fgColor-muted mb-2">
                <CheckIcon className="fgColor-success" /> Conversational documentation search
              </li>
              <li className="fgColor-muted mb-2">
                <CheckIcon className="fgColor-success" /> Summarization skills for pull requests
              </li>
              <li className="fgColor-muted mb-2">
                <CheckIcon className="fgColor-success" /> Fine-tuned models (coming soon)
              </li>
            </ul>
          </div>
          <Link href={cfeHelpLink}>Learn more about Copilot Enterprise</Link>
        </div>
      </div>
      <div className="text-small fgColor-muted mt-2">
        <div>
          By enabling and using GitHub Copilot you agree to the{' '}
          <Link inline href={copilotTocLink} className="fgColor-muted">
            GitHub Copilot Product Specific Terms
          </Link>
          .
        </div>
      </div>
    </div>
  )
}

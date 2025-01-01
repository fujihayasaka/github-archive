import {Link} from '@primer/react'
import styles from '../marketplace.module.css'
import ListingBodySection from './ListingBodySection'

export const CopilotListingRequirement = () => {
  return (
    <ListingBodySection title="Requirements">
      <div
        className={`${styles['marketplace-content-container']} ${styles['marketplace-content-container--less-padding']}`}
      >
        <p className="m-0" data-testid="copilot-listing-requirement">
          Copilot Extensions require an active{' '}
          <Link inline href="https://github.com/features/copilot/plans">
            GitHub Copilot license
          </Link>
          .
        </p>
      </div>
    </ListingBodySection>
  )
}

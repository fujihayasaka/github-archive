import {GitHubAvatar} from '@github-ui/github-avatar'
import {testIdProps} from '@github-ui/test-id-props'
import {HeartFillIcon, HeartIcon} from '@primer/octicons-react'
import {Button, Link} from '@primer/react'
import type {Column} from '@primer/react/experimental'
import DependenciesDialogBox from './DependenciesDialogBox'
import type {SponsorableData} from './types'

import styles from './Columns.module.css'

export const maintainerColumn: Column<SponsorableData> = {
  id: 'sponsorableName',
  header: 'Maintainer',
  field: 'sponsorableName',
  renderCell: (item: SponsorableData) => {
    return (
      <Link href={`/sponsors/${item.sponsorableName}`}>
        <div className={styles.Box}>
          <GitHubAvatar src={item.sponsorableAvatarUrl} square={item.sponsorableIsOrg} size={26} />
          <span className={styles.Text}>{`${item.sponsorableName}`}</span>
        </div>
      </Link>
    )
  },
}

export const dependenciesColumn = (
  orgName: string,
  handleLinkClick: (sponsorableName: string) => void,
  handleClose: (sponsorableName: string) => void,
  openPopups: {[key: string]: boolean},
  selectedSponsorable: string,
): Column<SponsorableData> => {
  return {
    id: 'sponsorableDependencies',
    header: 'Your dependencies they maintain or own',
    field: 'dependenciesArray',
    renderCell: (item: SponsorableData) => {
      return (
        <div>
          <span>
            {item?.dependenciesArray[0] ? (
              <>
                <span className={styles.Text_1}>{item.dependenciesArray[0].name}</span>
                {item?.dependenciesArray[1] && (
                  <span className={styles.Text_1}>{`, ${item.dependenciesArray[1].name}`}</span>
                )}
              </>
            ) : null}
          </span>
          {item.dependencyCount > 2 && (
            <>
              <Link
                onClick={() => handleLinkClick(item.sponsorableName)}
                style={{cursor: 'pointer'}}
                {...testIdProps('show-more-link')}
              >
                <span className="ml-1">{item.dependencyCount > 2 ? `+${item.dependencyCount - 2} more` : ''}</span>
              </Link>
              <DependenciesDialogBox
                isOpen={openPopups[item.sponsorableName] || false}
                setIsOpen={() => handleClose(item.sponsorableName)}
                dependencyCount={item.dependencyCount}
                orgName={orgName}
                sponsorableName={selectedSponsorable}
              />
            </>
          )}
        </div>
      )
    },
  }
}

export const recentActivityColumn: Column<SponsorableData> = {
  id: 'recentActivity',
  header: 'Recent activity',
  field: 'recentActivity',
  renderCell: (item: SponsorableData) => {
    return (
      item.recentActivity && (
        <span className={styles.Text_1} {...testIdProps('recent-activity')}>
          {item.recentActivity}
        </span>
      )
    )
  },
}

export const sponsorColumn = (orgName: string): Column<SponsorableData> => {
  return {
    id: 'sponsor',
    header: () => <span className="sr-only">Actions</span>,
    width: 'auto',
    renderCell: (item: SponsorableData) => {
      const link = `/sponsors/${item.sponsorableName}?sponsor=${orgName}`
      return (
        <Button
          as="a"
          size="small"
          href={link}
          leadingVisual={item.viewerIsSponsor ? HeartFillIcon : HeartIcon}
          aria-label={item.viewerIsSponsor ? 'Sponsoring' : 'Sponsor'}
          className={styles.Button}
          {...testIdProps('sponsor-button')}
        />
      )
    },
  }
}

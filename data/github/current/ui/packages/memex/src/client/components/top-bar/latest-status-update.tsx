import {testIdProps} from '@github-ui/test-id-props'
import {Button, RelativeTime, Token} from '@primer/react'
import {useCallback, useState} from 'react'

import {StatusUpdateOpenCurrent} from '../../api/stats/contracts'
import {formatDateString} from '../../helpers/parsing'
import {ViewerPrivileges} from '../../helpers/viewer-privileges'
import {usePostStats} from '../../hooks/common/use-post-stats'
import {useSidePanel} from '../../hooks/use-side-panel'
import {useStatusUpdates} from '../../state-providers/status-updates/status-updates-context'
import {SingleSelectToken} from '../fields/single-select/single-select-token'
import styles from './latest-status-update.module.css'

export const LatestStatusUpdate = () => {
  const {latestStatusItem} = useStatusUpdates()
  const {openPaneInfo} = useSidePanel()
  const {hasWritePermissions} = ViewerPrivileges()
  const {postStats} = usePostStats()
  const [showRelativeTime, setShowRelativeTime] = useState(false)

  const statusOption = latestStatusItem?.statusValue.status
  const openSidePanel = useCallback(() => {
    openPaneInfo(latestStatusItem?.id)

    const statsContext = latestStatusItem
      ? {
          id: latestStatusItem.id,
          status: latestStatusItem.statusValue.status?.name,
          startDate: latestStatusItem.statusValue.startDate,
          targetDate: latestStatusItem.statusValue.targetDate,
        }
      : {}

    postStats({
      name: StatusUpdateOpenCurrent,
      context: JSON.stringify(statsContext),
    })
  }, [latestStatusItem, openPaneInfo, postStats])
  // if the user is a viwer, they won't see the null state button
  return hasWritePermissions || statusOption ? (
    <div {...testIdProps('latest-status-update')}>
      {statusOption ? (
        <Button
          variant="invisible"
          onClick={openSidePanel}
          onMouseOver={() => setShowRelativeTime(true)}
          onMouseLeave={() => setShowRelativeTime(false)}
          aria-label={`View latest ${statusOption.name} status updated ${formatDateString(
            new Date(latestStatusItem.updatedAt),
          )}`}
          className={styles.latestStatusUpdate}
        >
          {showRelativeTime && (
            <span {...testIdProps('latest-status-update-token-button-text')}>
              Updated <RelativeTime datetime={latestStatusItem.updatedAt} className={styles.RelativeTime} />{' '}
            </span>
          )}
          <SingleSelectToken
            {...testIdProps('latest-status-update-token-button')}
            as="span"
            option={statusOption}
            className={styles.SingleSelectToken}
          />
        </Button>
      ) : (
        <Button variant="invisible" onClick={openSidePanel}>
          <Token
            {...testIdProps('latest-status-update-null-button')}
            text="Add status update"
            className={styles.SingleSelectToken}
          />
        </Button>
      )}
    </div>
  ) : null
}

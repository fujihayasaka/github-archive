// this is restricted import is a false positive meant to catch **/pull-requests/** in app/assets/modules
// eslint-disable-next-line no-restricted-imports
import {useRepondToAliveUpdate} from '@github-ui/pull-requests/hooks/live-update'
import {Button, Link} from '@primer/react'
import {useState} from 'react'
import styles from './RefreshButton.module.css'
import {SyncIcon} from '@primer/octicons-react'

export function RefreshButton({aliveChannel, pathName}: {aliveChannel: string; pathName: string}) {
  const [show, setShow] = useState(false)

  const handler = () => {
    // eventually we might do other/smarter things than refreshing the page
    // ie - TSQ query invalidation, payload refreshes, etc
    setShow(true)
  }

  // we only need to display the refresh button when the base or head sha has changed (via git_updated)
  useRepondToAliveUpdate(aliveChannel, handler, {git_updated: true})

  if (!show) {
    return null
  }

  return (
    <Button
      as={Link}
      variant="invisible"
      href={`${pathName}/files`}
      className={styles.refresh}
      leadingVisual={SyncIcon}
    >
      Refresh
    </Button>
  )
}

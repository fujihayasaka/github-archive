import {Dialog} from '@primer/react/experimental'
import {Link} from '@primer/react'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
import {useEffect} from 'react'

import styles from './BranchNextStepDesktop.module.css'

export type BranchNextStepDesktopProps = {
  branch: string | null
  repository: string
  owner: string
  onClose: () => void
  flashes?: React.ReactNode
}

export const BranchNextStepDesktop = ({branch, repository, owner, onClose, flashes}: BranchNextStepDesktopProps) => {
  const desktopUrl =
    owner && repository
      ? `x-github-client://openRepo/${ssrSafeWindow?.origin}/${owner}/${repository}?branch=${branch}`
      : undefined

  useEffect(() => {
    if (ssrSafeWindow && desktopUrl) {
      ssrSafeWindow.location.replace(desktopUrl)
    }
  }, [desktopUrl])

  return (
    <Dialog width="large" height="auto" title="Opening branch in GitHub Desktop..." onClose={onClose}>
      {flashes}
      <span className={styles.text}>
        If nothing happens, make sure&nbsp;
        <Link inline target="_blank" href="https://desktop.github.com/" rel="noreferrer">
          GitHub Desktop
        </Link>
        &nbsp;is installed and set up properly, then&nbsp;
        <Link inline href={desktopUrl}>
          try again
        </Link>
        .
      </span>
    </Dialog>
  )
}

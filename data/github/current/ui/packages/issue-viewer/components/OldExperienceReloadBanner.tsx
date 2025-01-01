import {ssrSafeDocument} from '@github-ui/ssr-utils'
import {Box, Link} from '@primer/react'
import {createPath, useLocation} from 'react-router-dom'

export function OldExperienceReloadBanner() {
  const {pathname, search, hash} = useLocation()
  let modifiedSearch = search
  if (!search.includes('_features=!issues_react_v2')) {
    if (search) {
      modifiedSearch = `${search}&_features=!issues_react_v2`
    } else {
      modifiedSearch = '?_features=!issues_react_v2'
    }
  }

  const pathWithIssuesReactV2Disabled = createPath({
    pathname,
    search: modifiedSearch,
    hash,
  })

  const onClick = (e: React.MouseEvent) => {
    if (ssrSafeDocument?.location?.href) {
      // if the mouse wheel is clicked, do nothing
      if (e.button === 1) return

      // if a keyboard modifier is used, do nothing
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return

      e.preventDefault()
      ssrSafeDocument.location.href = new URL(pathWithIssuesReactV2Disabled, window.location.origin).toString()
    }
  }

  return (
    <Box sx={{m: 3, mt: 2, ml: 2}}>
      <Link onClick={onClick} sx={{fontSize: 0, color: 'fg.subtle'}} href={pathWithIssuesReactV2Disabled}>
        👀 Reload with classic experience
      </Link>
    </Box>
  )
}

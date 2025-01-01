import {PersonIcon} from '@primer/octicons-react'
import {Box} from '@primer/react'
import {announce} from '@github-ui/aria-live'
import {debounce} from '@github/mini-throttle'
import {useEffect} from 'react'

const debounceAnnouncement = debounce(announce, 300)
const headerText = 'Nothing matched your search criteria'

export function NoSearchResultsBlankslate() {
  useEffect(() => {
    debounceAnnouncement(headerText)
  }) // No dependency array, so effect runs on every render

  return (
    <div className="Box rounded-top-0 blankslate">
      <PersonIcon size={24} className="fgColor-subtle" />
      <div className="blankslate-heading">{headerText}</div>
      <Box sx={{alignItems: 'center', display: 'flex', flexDirection: 'column'}}>
        <p>Make sure that everything is spelled correctly or try different keywords.</p>
      </Box>
    </div>
  )
}

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
    <Box className="Box blankslate" sx={{borderTopRightRadius: 0, borderTopLeftRadius: 0}}>
      <PersonIcon size={24} className="fgColor-subtle mb-3" />
      <h2 className="blankslate-heading">{headerText}</h2>
      <Box sx={{alignItems: 'center', display: 'flex', flexDirection: 'column'}}>
        <p>Make sure that everything is spelt correctly or try different keywords.</p>
      </Box>
    </Box>
  )
}

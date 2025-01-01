import {useFragment} from 'react-relay'
import {graphql} from 'relay-runtime'
import type {MilestoneRowTitle$key} from './__generated__/MilestoneRowTitle.graphql'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {useNavigate} from '@github-ui/use-navigate'
import {useIsPlatform} from '@github-ui/use-is-platform'
import {useCallback} from 'react'

type MilestoneRowProps = {
  milestone: MilestoneRowTitle$key
}

export function MilestoneRowTitle({milestone}: MilestoneRowProps) {
  const data = useFragment(
    graphql`
      fragment MilestoneRowTitle on Milestone {
        title
        url
      }
    `,
    milestone,
  )
  const href = data.url
  const isMac = useIsPlatform(['mac'])
  const navigate = useNavigate()
  const onClick = useCallback(
    (event: React.MouseEvent<HTMLAnchorElement>) => {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      const isMetaKey = isMac ? event.metaKey : event.ctrlKey
      if (isMetaKey) {
        return
      }

      event.preventDefault()
      const url = new URL(href, window.location.origin)
      const path = url.pathname
      navigate(path)
    },
    [href, isMac, navigate],
  )

  return <ListItemTitle value={data.title} href={data.url} onClick={onClick} />
}

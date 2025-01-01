import {TableIcon} from '@primer/octicons-react'
import {Link} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

type ProjectV2Props = {
  url: string
  title: string
}

export function ProjectV2({url, title}: ProjectV2Props): JSX.Element {
  return (
    <>
      <Octicon icon={TableIcon} />{' '}
      <Link href={url} sx={{color: 'fg.default'}} inline>
        {title}
      </Link>
    </>
  )
}

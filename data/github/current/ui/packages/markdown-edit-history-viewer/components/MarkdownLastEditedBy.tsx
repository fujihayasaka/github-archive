import {Link} from '@primer/react'
import {graphql, useFragment} from 'react-relay'

import {LABELS} from '../constants/labels'
import type {MarkdownLastEditedBy$key} from './__generated__/MarkdownLastEditedBy.graphql'
import styles from './MarkdownLastEditedBy.module.css'

type MarkdownLastEditedByProps = {
  editInformation?: MarkdownLastEditedBy$key
  includeSeparator?: boolean
  forceUnderline?: boolean
}

export function MarkdownLastEditedBy({editInformation, includeSeparator, forceUnderline}: MarkdownLastEditedByProps) {
  const data = useFragment(
    graphql`
      fragment MarkdownLastEditedBy on Comment {
        viewerCanReadUserContentEdits
        lastUserContentEdit {
          editor {
            url
            login
          }
        }
      }
    `,
    editInformation,
  )

  if (!data || !data.viewerCanReadUserContentEdits || !data.lastUserContentEdit || !data.lastUserContentEdit.editor) {
    return null
  }

  const {login, url} = data.lastUserContentEdit.editor

  return (
    <span className={styles.container}>
      {includeSeparator && <span> &middot; </span>}
      <span>
        {`${LABELS.editHistory.editedBy} `}
        <Link sx={{color: 'fg.muted'}} href={url} inline={forceUnderline}>
          {login}
        </Link>
      </span>
    </span>
  )
}

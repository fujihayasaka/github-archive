import React from 'react'

import {XIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {SkeletonBox} from '@primer/react/experimental'

export function AttachmentItem(
  props: React.PropsWithChildren<{
    onRemove: () => void
  }>,
) {
  return (
    <div style={{maxWidth: 'min-content'}}>
      <React.Suspense fallback={<Loading />}>
        <div className="d-flex flex-column color-bg-subtle p-2 gap-2 rounded-2">
          <div className="d-flex rounded-2" style={{height: '100px', overflow: 'clip', lineHeight: '0'}}>
            {props.children}
          </div>
          <Button
            sx={{color: 'fg.subtle'}}
            variant="invisible"
            trailingVisual={XIcon}
            aria-label="Remove file"
            onClick={props.onRemove}
          >
            Remove
          </Button>
        </div>
      </React.Suspense>
    </div>
  )
}

function Loading() {
  return <SkeletonBox sx={{width: 100, height: 'max(100%, 75px)', borderRadius: 2}} />
}

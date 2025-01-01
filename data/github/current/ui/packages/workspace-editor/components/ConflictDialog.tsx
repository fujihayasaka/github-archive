import {Dialog} from '@primer/react'
import type {ParsedDiff} from 'diff'

import {mapPatchToDiffLines} from '../utilities/diff-helpers'
import type {ExtendedDiff} from '../utilities/file-syncer-types'
import {Diff} from './Diff'

export function ConflictDialog({
  patchIncluded,
  patch,
  closeConflictDialog,
}: {
  patchIncluded: boolean
  patch: ExtendedDiff | ParsedDiff | undefined
  closeConflictDialog: () => void
}) {
  let conflictingPatches: string[] = []
  if (!patchIncluded && patch) {
    conflictingPatches = [
      ...new Set(
        patch['hunks'].map(hunk => {
          const filteredLines = hunk.lines.filter(line => line.startsWith('-') || line.startsWith('+'))
          return `[ ${filteredLines.join(', ')} ]`
        }),
      ),
    ]
  }

  if (conflictingPatches.length > 0 && patch) {
    return (
      <Dialog
        title={'Conflict'}
        onClose={closeConflictDialog}
        footerButtons={[
          {
            buttonType: 'danger',
            content: 'Close and discard changes',
            onClick: closeConflictDialog,
          },
        ]}
      >
        <p>
          The following changes to the underlying branch conflict with this Workspace session and cannot be resolved in
          the editor.
        </p>
        <Dialog.Body>
          <Diff fileName={patch.oldFileName || patch.newFileName || ''} outdated lines={mapPatchToDiffLines(patch)} />
        </Dialog.Body>
      </Dialog>
    )
  }
}

import {useMemo} from 'react'
import type {Markers} from '../page-data/loaders/use-markers-data'
import type {ThreadPreview} from '../page-data/payloads/thread-previews'

//because the thread information for suggested changes requires a subject, we have to parse the subject from the
//threadPreviews we get back for the toolbar. In the future when we remove the threadPreviews, we will need to move
//this to build and insert the subject where we locate the markers within the diff lines.
export function useStitchSubjectIntoThreads(
  initialMarkers: Markers | undefined,
  threadPreviews: ThreadPreview[],
): void {
  useMemo(() => {
    for (const [_, value] of Object.entries(initialMarkers?.threads ?? {})) {
      if (value) {
        const threadPreviewWithId = threadPreviews.filter(
          //TODO: we should update the types to represent the fact that the thread.id value is a number not a string
          thread => parseInt(thread.threadId) === (value.id as unknown as number),
        )
        if (threadPreviewWithId.length === 1) {
          value.subject = threadPreviewWithId[0]?.subject
        }
      }
    }
    return initialMarkers
  }, [initialMarkers, threadPreviews])
}

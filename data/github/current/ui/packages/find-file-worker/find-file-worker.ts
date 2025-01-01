import {findFileWorkerJob, type FindFileRequest} from '@github-ui/code-view-shared/worker-jobs/find-file'

declare const self: Worker

self.onmessage = (message: {data: FindFileRequest}) => {
  self.postMessage(findFileWorkerJob(message))
}

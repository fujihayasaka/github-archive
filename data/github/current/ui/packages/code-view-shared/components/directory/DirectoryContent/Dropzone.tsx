import {FileIcon} from '@primer/octicons-react'

interface Props {
  uploadUrl: string
}

export function Dropzone({uploadUrl}: Props) {
  return (
    <document-dropzone>
      <div
        className="repo-file-upload-tree-target js-upload-manifest-tree-view"
        data-testid="dragzone"
        data-drop-url={uploadUrl}
        data-target="document-dropzone.dropContainer"
      >
        <div className="repo-file-upload-outline">
          <div className="repo-file-upload-slate">
            <div className="fgColor-muted">
              <FileIcon size={32} />
            </div>
            <h2 aria-hidden="true">Drop to upload your files</h2>
          </div>
        </div>
      </div>
    </document-dropzone>
  )
}

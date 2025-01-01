import {useClientValue} from '@github-ui/use-client-value'
import {Box, Flash, Spinner, type BetterSystemStyleObject} from '@primer/react'

import React from 'react'

import {DEFAULT_RENDERER_HEIGHT, RenderState, useFileRenderer} from './use-file-renderer'

import styles from './FileRendererBlob.module.css'

const MAX_BLOB_SIZE = 200_000_000 // 200MB
const MAX_NOTEBOOK_SIZE = 30_000_000 // 30MB

export interface FileRendererBlobData {
  identityUuid: string
  size: number
  type: string
  url: string
}

export default function FileRendererBlob({identityUuid, size, type, url}: FileRendererBlobData) {
  const [tempOrigin] = useClientValue(() => window.location.origin, 'https://www.github.com', [])
  const origin = new URL(url, tempOrigin).origin
  const {renderState, errorMsg, iFrameRef, containerRef} = useFileRenderer(origin)

  const isNotebook = type === 'ipynb'
  if ((isNotebook && size > MAX_NOTEBOOK_SIZE) || size > MAX_BLOB_SIZE) {
    return <Flash variant="danger">Sorry, this is too big to display.</Flash>
  }

  // Setting display: none or visibility: hidden on the iframe prevents it from loading.
  // Instead, while the content is not ready, make it tiny and hide it in the lower right corner.
  const iframeStateSX: BetterSystemStyleObject =
    renderState !== RenderState.READY
      ? {height: '1px', width: '1px', position: 'fixed', bottom: 0, right: 0}
      : {height: '100%', width: '100%'}

  const rendererReadySx = {height: DEFAULT_RENDERER_HEIGHT, padding: 0, background: 'none'} as const
  const nonErrorSx = {
    borderBottomLeftRadius: '6px',
    borderBottomRightRadius: '6px',
    lineHeight: '0',
    padding: 5,
    textAlign: 'center',
  } as const

  return (
    <div className={styles.FileRendererWrapper}>
      <Box
        data-hpc
        data-host={origin}
        data-type={type}
        ref={containerRef}
        sx={{
          ...(renderState !== RenderState.ERROR ? nonErrorSx : {}),
          ...(renderState === RenderState.READY ? rendererReadySx : {}),
        }}
        className={styles.FileRendererViewport}
      >
        {renderState === RenderState.ERROR ? (
          <FileRendererErrorMessage error={errorMsg} />
        ) : renderState !== RenderState.READY ? (
          <Spinner size="large" className={styles.loadingIndicator} />
        ) : null}

        {renderState !== RenderState.ERROR && (
          <Box
            as="iframe"
            ref={iFrameRef}
            src={`${url}#${identityUuid}`}
            // eslint-disable-next-line @eslint-react/dom/no-unsafe-iframe-sandbox
            sandbox="allow-scripts allow-same-origin allow-top-navigation"
            sx={{
              ...iframeStateSX,
            }}
            name={identityUuid}
            title="File display"
            className={styles.fileContentFrame}
          >
            Viewer requires iframe.
          </Box>
        )}
      </Box>
    </div>
  )
}

function FileRendererErrorMessage({error}: {error: string | null}) {
  if (!error) {
    return <Flash variant="danger">Unable to render code block</Flash>
  }

  const msgLines = error.split('\n')
  return (
    <Flash variant="danger">
      <p className={styles.errorMessageHeading}>Error rendering embedded code</p>
      <p>
        {msgLines.map((line, index) => (
          // eslint-disable-next-line @eslint-react/no-array-index-key
          <React.Fragment key={`error-line-${index}`}>
            {line}
            <br />
          </React.Fragment>
        ))}
      </p>
    </Flash>
  )
}

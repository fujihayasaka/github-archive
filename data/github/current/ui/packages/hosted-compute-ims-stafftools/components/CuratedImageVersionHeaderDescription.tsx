import {Box, Stack} from '@primer/react'
import type {ImageDefinition, ImageVersion} from '../types/types'
import {ImageVersionEnabledState} from './ImageVersionEnabledState'
import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {formatDateString} from '../helpers/utils'

interface CuratedImageVersionHeaderDescriptionnProps {
  imageDefinition: ImageDefinition
  imageVersion: ImageVersion
}

export function CuratedImageVersionHeaderDescription(props: CuratedImageVersionHeaderDescriptionnProps) {
  return (
    <Box
      sx={{
        borderTop: 'var(--borderWidth-thin) solid var(--borderColor-muted)',
      }}
    >
      <Box
        sx={{
          borderBottom: 'var(--borderWidth-thin) solid var(--borderColor-muted)',
          p: 2,
        }}
      >
        <div className="col-9 d-inline-block v-align-top">
          <div>
            <span className="color-fg-muted">Image Version: </span>
            <span>{props.imageVersion.version}</span>
          </div>
          <div>
            <span className="color-fg-muted">Image Version Id: </span>
            <span>{props.imageVersion.id}</span>
          </div>
          <div>
            <span className="color-fg-muted">Created At: </span>
            <span>{formatDateString(new Date(props.imageVersion.createdAt))}</span>
          </div>
          <div>
            <span className="color-fg-muted">State: </span>
            <span>
              {props.imageVersion.state}
              {props.imageVersion.stateDetails && <> ({props.imageVersion.stateDetails})</>}
            </span>
          </div>
        </div>
        <div className="col-3 d-inline-block v-align-top">
          <div>
            <span className="color-fg-muted">VM Generation: </span>
            <span>{props.imageVersion.vmGeneration}</span>
          </div>
          <div>
            <span className="color-fg-muted">OS State: </span>
            <span>{props.imageVersion.osState}</span>
          </div>
          <div>
            <span className="color-fg-muted">Agent User: </span>
            <span>{props.imageVersion.agentUser || 'runner'}</span>
          </div>
          <div>
            <span className="color-fg-muted">Size: </span>
            <span>{props.imageVersion.sizeGb} GB</span>
          </div>
          <div>
            <span className="color-fg-muted">Enabled: </span>
            <span>
              <ImageVersionEnabledState imageVersion={props.imageVersion} />
            </span>
          </div>
        </div>
      </Box>
      <Box
        sx={{
          borderBottom: 'var(--borderWidth-thin) solid var(--borderColor-muted)',
          p: 2,
        }}
      >
        <div>
          <span className="color-fg-muted">Azure Purchase Plan: </span>
          {props.imageVersion.azurePurchasePlan ? (
            <span>{props.imageVersion.azurePurchasePlan}</span>
          ) : (
            <span>&#60;null&#62;</span>
          )}
        </div>
        {ImageVersionResourceId(props.imageVersion)}
      </Box>
    </Box>
  )
}

function ImageVersionResourceId(imageVersion: ImageVersion): JSX.Element {
  const resourceIdElement = imageVersion.resourceId ? (
    <Box
      sx={{
        backgroundColor: 'var(--bgColor-muted, var(--color-canvas-subtle)) !important',
        padding: 'var(--base-size-16, 16px) !important',
        borderRadius: 'var(--borderRadius-medium, 6px) !important',
        borderColor: 'var(--control-bgColor-disabled,var(--color-input-disabled-bg,rgba(175,184,193,0.2)))',
        border:
          '1px solid var(--control-borderColor-rest,var(--borderColor-default,var(--color-border-default,#d0d7de)))',
        wordBreak: 'break-all',
      }}
    >
      <Stack direction="horizontal" gap="condensed" align="center">
        <Stack.Item grow>
          <span>{imageVersion.resourceId}</span>
        </Stack.Item>
        <CopyToClipboardButton
          className="ml-1 mr-0"
          sx={{width: '32px'}}
          textToCopy={imageVersion.resourceId}
          ariaLabel={'Copy to clipboard'}
          tooltipProps={{direction: 'nw'}}
        />
      </Stack>
    </Box>
  ) : (
    <span>&#60;null&#62;</span>
  )

  return (
    <div>
      <span className="color-fg-muted">Resource Id: </span>
      <span>{resourceIdElement}</span>
    </div>
  )
}

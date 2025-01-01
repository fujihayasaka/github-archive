import type {
  CustomCopilotId,
  CustomCopilotVisibility,
  IndexCustomCopilot,
} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {customCopilotMatchesId, getCopilotSpacePath} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {copyText} from '@github-ui/copy-to-clipboard'
import {useFetchCustomCopilots, useFetchVisibilitySettings} from '@github-ui/custom-copilots/hooks'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {LinkIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button, Dialog, Stack, TextInput, Truncate} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {useEffect, useMemo, useRef, useState} from 'react'

import {useUpsertCopilotSpace} from './hooks/use-upsert-copilot-space'
import styles from './SpaceVisibilityDialog.module.css'

interface CopilotSpaceVisibilityDialogProps {
  closeDialog: () => void
  customCopilotId: CustomCopilotId
}

interface VisibilitySettingsProps {
  isSpaceLoading: boolean
  copilotSpace?: IndexCustomCopilot
  onError: (errorMessages: Record<string, string>) => void
}

interface VisibilitySelectProps {
  copilotSpace: IndexCustomCopilot
  onError: (errorMessages: Record<string, string>) => void
}

export function SpaceVisibilityDialog(props: CopilotSpaceVisibilityDialogProps) {
  const {closeDialog, customCopilotId} = props
  const renderFooter = () => <CopilotSpaceVisibilityDialogFooter />
  const [errorMessages, setErrorMessages] = useState<Record<string, string | undefined>>({})

  const [copied, setCopied] = useState(false)
  const timeoutRef = useRef<NodeJS.Timeout | null>(null)

  // Clean up timeout when component unmounts
  useEffect(() => {
    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current)
        timeoutRef.current = null
      }
    }
  }, [])

  const sharedLink = useMemo(() => {
    return `${ssrSafeLocation.origin}${getCopilotSpacePath(props.customCopilotId)}`
  }, [props.customCopilotId])

  const copySharedLink = () => {
    void copyText(sharedLink)
    setCopied(true)
    if (timeoutRef.current) {
      clearTimeout(timeoutRef.current)
    }
    timeoutRef.current = setTimeout(() => {
      setCopied(false)
      timeoutRef.current = null
    }, 2000)
  }

  const {data: customCopilots, isLoading: isSpaceLoading} = useFetchCustomCopilots(true)
  const copilotSpace = customCopilots?.find(copilot => customCopilotMatchesId(copilot, customCopilotId))

  return (
    <Dialog
      title={'Share this space'}
      renderFooter={renderFooter}
      onClose={closeDialog}
      className={styles.spaceVisibilityDialog}
      width="large"
    >
      {errorMessages.base || errorMessages.visibility ? (
        <Banner
          hideTitle
          title="Unable to update space visibility"
          description={errorMessages.visibility || errorMessages.base}
          aria-label="Critical"
          variant="critical"
          className={styles.errorBanner}
        />
      ) : null}
      <Stack data-testid="custom-copilot-visibility" gap="condensed">
        <Stack direction="vertical" gap="condensed" align="start">
          <span className="text-small text-bold color-fg-muted mb-1">Link</span>
          <div className={styles.copyLinkSection}>
            <TextInput block value={sharedLink} readOnly className="color-fg-muted" />
            <div style={{position: 'relative'}} className={styles.copyLinkButtonContainer}>
              {/* Custom styling here allows us to dynamically maintain the same wider button width after a user presses it */}
              <Button
                className={styles.copyLinkButton}
                leadingVisual={LinkIcon}
                variant="default"
                onClick={copySharedLink}
                style={{visibility: copied ? 'hidden' : 'visible'}}
                tabIndex={copied ? -1 : 1}
                aria-hidden={copied ? 'true' : 'false'}
                disabled={isSpaceLoading || !copilotSpace || copilotSpace?.visibility === 'private'}
              >
                Copy link
              </Button>
              {copied && (
                <Button variant="default" className={styles.copiedLinkButton} tabIndex={-1} aria-hidden="false">
                  Link copied
                </Button>
              )}
            </div>
          </div>
        </Stack>
        <Stack direction="vertical" gap="condensed" align="start">
          <span className="text-small text-bold color-fg-muted mt-2">Base role</span>
          <VisibilitySettings
            onError={setErrorMessages}
            copilotSpace={copilotSpace}
            isSpaceLoading={isSpaceLoading}
            {...props}
          />
        </Stack>
      </Stack>
    </Dialog>
  )
}

function VisibilitySettings({copilotSpace, isSpaceLoading, onError}: VisibilitySettingsProps) {
  const {
    data: visibilityData,
    isLoading: isVisibilityLoading,
    error: isVisibilityError,
  } = useFetchVisibilitySettings(copilotSpace?.owner || '', copilotSpace?.id ?? -1)

  useEffect(() => {
    if (!isSpaceLoading && !isVisibilityLoading && (!copilotSpace || !visibilityData)) {
      onError({visibility: "Could not load your space's visibility settings"})
    }
  }, [isSpaceLoading, isVisibilityLoading, copilotSpace, visibilityData, onError])

  if (isSpaceLoading) {
    return <div className="color-fg-muted p-2">Loading space information...</div>
  } else if (!copilotSpace) {
    return <div className="color-fg-muted p-2">Could not load data for your space.</div>
  }

  const orgLogin = copilotSpace.owner
  const memberCount = visibilityData?.memberCount

  return (
    <div className="width-full d-flex flex-items-center flex-justify-between">
      <div className="d-flex flex-items-center mt-1">
        <GitHubAvatar src={copilotSpace.ownerAvatar} className="mr-2" square size={32} />
        <div className="d-flex flex-column">
          <span className="ml-1">
            <Truncate maxWidth="230px" title={copilotSpace.ownerDisplayName} inline>
              <b>{copilotSpace.ownerDisplayName}</b>
            </Truncate>
            <span className="color-fg-muted ml-1">(owner)</span>
          </span>
          {orgLogin && (
            <>
              {!isVisibilityLoading && memberCount !== null && (
                <span className="text-small color-fg-muted ml-1">
                  {memberCount} {memberCount === 1 ? 'person' : 'people'}
                </span>
              )}
              {(isVisibilityLoading || isVisibilityError || memberCount === null) && (
                <span className="text-small color-fg-muted ml-1">Organization</span>
              )}
            </>
          )}
        </div>
      </div>

      <VisibilitySelect onError={onError} copilotSpace={copilotSpace} />
    </div>
  )
}

const VisibilityOptions: Array<{text: string; value: CustomCopilotVisibility}> = [
  {text: 'No access', value: 'private'},
  {text: 'Read', value: 'org_public'},
]

function VisibilitySelect({copilotSpace, onError}: VisibilitySelectProps) {
  const [open, setOpen] = useState(false)

  const buttonRef = useRef(null)
  const currentVisibility = VisibilityOptions.find(opt => opt.value === copilotSpace.visibility)

  const {upsertCopilotSpace, isPending} = useUpsertCopilotSpace(copilotSpace)

  async function updateSpaceVisibility(value: CustomCopilotVisibility) {
    if (isPending) return
    try {
      await upsertCopilotSpace({visibility: value})
    } catch {
      onError({base: "An error occurred while updating your space's visibility."})
    } finally {
      setOpen(false)
    }
  }

  return copilotSpace.editable ? (
    <ActionMenu onOpenChange={setOpen} anchorRef={buttonRef} open={open}>
      <ActionMenu.Button
        loading={isPending}
        variant="invisible"
        className="text-small"
        ref={buttonRef}
        onClick={() => setOpen(true)}
      >
        <Truncate title={currentVisibility?.text || ''} inline className="mr-1">
          {currentVisibility?.text}
        </Truncate>
      </ActionMenu.Button>
      <ActionMenu.Overlay side="outside-bottom" align="end">
        <ActionList selectionVariant="single">
          {VisibilityOptions.map(option => (
            <ActionList.Item
              selected={option.value === currentVisibility?.value}
              key={option.value}
              onSelect={() => updateSpaceVisibility(option.value)}
            >
              <span className="text-small">{option.text}</span>
            </ActionList.Item>
          ))}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  ) : (
    <div>
      <Truncate title={currentVisibility?.text || ''} className="text-small text-light">
        {currentVisibility?.text}
      </Truncate>
    </div>
  )
}

function CopilotSpaceVisibilityDialogFooter() {
  return (
    <Dialog.Footer
      style={{
        backgroundColor: 'var(--bgColor-muted)',
        borderBottomLeftRadius: 'var(--borderRadius-large, 0.75rem)', // otherwise lost when background-color is set here
        borderBottomRightRadius: 'var(--borderRadius-large, 0.75rem)', // otherwise lost when background-color is set here
      }}
      className="color-fg-muted flex-justify-center text-small p-2"
    >
      <span className={styles.dialogFooterText}>
        This space may include private content. Viewers need content access.
      </span>
    </Dialog.Footer>
  )
}

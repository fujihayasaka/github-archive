import {ButtonGroup, Button, IconButton} from '@primer/react'
import {TriangleDownIcon} from '@primer/octicons-react'
import {useState, useCallback} from 'react'
import {CodeSnippet} from './CodeSnippet'
import {VersionPicker} from './VersionPicker'
import {sendEvent} from '@github-ui/hydro-analytics'
import type {ReleaseData, Repository} from '../../types'
import type {ActionListing} from '@github-ui/marketplace-common'
import styles from '../../marketplace.module.css'

interface VersionButtonProps {
  releaseData: ReleaseData
  action: ActionListing
  repository: Repository
}

export function VersionButton(props: VersionButtonProps) {
  const {releaseData, action, repository} = props
  const {selectedRelease, latestRelease, releases} = releaseData

  // Handle code snippet dialog open and close
  const [isCodeSnippetOpen, setIsCodeSnippetOpen] = useState(false)
  const onCodeSnippetClose = useCallback(() => setIsCodeSnippetOpen(false), [])

  // Handle version picker dialog open and close
  const [isVersionPickerOpen, setIsVersionPickerOpen] = useState(false)
  const onVersionPickerClose = useCallback(() => setIsVersionPickerOpen(false), [])

  return (
    <>
      <ButtonGroup className={styles.ButtonGroup}>
        <Button
          variant={'primary'}
          onClick={() => {
            setIsCodeSnippetOpen(!isCodeSnippetOpen)
            sendEvent('marketplace.action.click', {
              repository_action_id: action.globalRelayId,
              source_url: `${window.location}`,
              location: 'actions#show',
            })
          }}
          block
        >
          Use {selectedRelease ? selectedRelease.tagName : 'latest version'}
        </Button>
        <IconButton
          variant={'primary'}
          onClick={() => setIsVersionPickerOpen(!isVersionPickerOpen)}
          aria-label={'Choose a version'}
          icon={TriangleDownIcon}
        />
      </ButtonGroup>

      <CodeSnippet
        action={action}
        repository={repository}
        isOpen={isCodeSnippetOpen}
        onClose={onCodeSnippetClose}
        selectedRelease={selectedRelease}
        latestRelease={latestRelease}
      />

      <VersionPicker
        action={action}
        selectedRelease={selectedRelease}
        releases={releases}
        isOpen={isVersionPickerOpen}
        onClose={onVersionPickerClose}
      />
    </>
  )
}

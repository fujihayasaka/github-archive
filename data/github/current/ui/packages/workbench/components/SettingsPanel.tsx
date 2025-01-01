import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {useCurrentUser} from '@github-ui/current-user'
import {useMutation} from '@github-ui/react-query'
import {ScopedCommands} from '@github-ui/ui-commands'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {LinkExternalIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button, ConfirmationDialog, FormControl, Stack, Textarea} from '@primer/react'
import {useEffect, useState} from 'react'

import {useIterationHistory} from '../contexts/IterationHistoryContext'
import {ReadOnlyProvider, useReadOnly} from '../contexts/ReadOnlyContext'
import {useWorkbenchContext} from '../contexts/WorkbenchContext'
import {isError, useCheckName} from '../hooks/use-check-name'
import {Region, RegionState, useRegionState} from '../hooks/use-region-state'
import {useWorkbench, type UseWorkbenchReturn} from '../hooks/use-workbench'
import type {Iteration} from '../types/workbench-types'
import {NameInput} from './NameInput'
import styles from './SettingsPanel.module.css'

interface SettingsPanelProps {
  repositoryUrl: string | undefined
  onCreateRepository?: () => void
}

export function SettingsPanel({repositoryUrl, onCreateRepository}: SettingsPanelProps) {
  const workbench = useWorkbench()

  const {previousRefinements} = useIterationHistory()
  const {userAgentModelPreference, setUserAgentModelPreference} = useWorkbenchContext()
  const currentUser = useCurrentUser()

  const panelState = useRegionState(Region.SETTINGS)
  const readOnly = panelState === RegionState.READ_ONLY

  const [isDeleteConfirmationOpen, setIsDeleteConfirmationOpen] = useState(false)

  const {mutate: deleteSpark, isPending} = useMutation({
    mutationFn: async () => {
      await verifiedFetchJSON(`/copilot/spark/workbench/${workbench.id}`, {
        method: 'DELETE',
      })
    },
    onSuccess: () => {
      // eslint-disable-next-line react-hooks/react-compiler
      window.location.href = '/spark'
    },
  })

  const getRepositoryOwnerAndName = (url: string): string => {
    const match = url.match(/([^/]+)\/([^/]+)\/?$/)
    return `${match![1]}/${match![2]}`
  }

  return (
    <ReadOnlyProvider readOnly={readOnly}>
      <div className={styles.container}>
        <BasicForm
          name={workbench.name}
          description={workbench.description}
          isFetching={workbench.isFetching}
          previousRefinements={previousRefinements}
          updatePartialWorkbench={workbench.updatePartialWorkbench}
        />

        {currentUser?.isStaff && copilotFeatureFlags.workbenchDefaultSonnet4 && (
          <FormControl>
            <FormControl.Label className="mb-1">Agent model</FormControl.Label>
            <ActionMenu>
              <ActionMenu.Button disabled={readOnly}>{userAgentModelPreference}</ActionMenu.Button>
              <ActionMenu.Overlay width="auto">
                <ActionList selectionVariant="single">
                  <ActionList.Item
                    selected={userAgentModelPreference === 'claude-sonnet-4'}
                    onSelect={() => setUserAgentModelPreference('claude-sonnet-4')}
                  >
                    Claude Sonnet 4
                  </ActionList.Item>
                  <ActionList.Item
                    selected={userAgentModelPreference === 'claude-3.7-sonnet'}
                    onSelect={() => setUserAgentModelPreference('claude-3.7-sonnet')}
                  >
                    Claude Sonnet 3.7
                  </ActionList.Item>
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
          </FormControl>
        )}

        {repositoryUrl ? (
          <div>
            <div className={styles.dangerZoneTitle}>Repository</div>
            <p className={styles.subtitle}>
              Your spark’s code is available in the{' '}
              <span className="text-bold">{getRepositoryOwnerAndName(repositoryUrl)}</span> repository.
            </p>
            <Button as="a" href={repositoryUrl} target="_blank" trailingVisual={LinkExternalIcon}>
              View repository
            </Button>
          </div>
        ) : (
          <div>
            <div className={styles.dangerZoneTitle}>Repository</div>
            <p className={styles.subtitle}>
              Create a repository to invite collaborators and get access to your spark’s code.
            </p>
            <Button size="medium" variant="primary" onClick={onCreateRepository} disabled={readOnly}>
              Create repository
            </Button>
          </div>
        )}

        <div>
          <div className={styles.dangerZoneTitle}>Delete spark</div>
          <p className={styles.subtitle}>Once you delete a spark, there is no going back. Please be certain.</p>
          <Button size="medium" variant="danger" onClick={() => setIsDeleteConfirmationOpen(true)} loading={isPending}>
            Delete
          </Button>
          {isDeleteConfirmationOpen && (
            <ConfirmationDialog
              title="Delete spark"
              onClose={gesture => {
                if (gesture === 'confirm') {
                  deleteSpark()
                }
                setIsDeleteConfirmationOpen(false)
              }}
              confirmButtonContent="Delete"
              confirmButtonType="danger"
            >
              Are you sure you want to delete this spark? This action can’t be undone.
            </ConfirmationDialog>
          )}
        </div>
      </div>
    </ReadOnlyProvider>
  )
}

function BasicForm({
  name,
  description,
  isFetching,
  previousRefinements,
  updatePartialWorkbench,
}: {
  name: string
  description: string
  isFetching: boolean
  previousRefinements: Iteration[]
  updatePartialWorkbench: UseWorkbenchReturn['updatePartialWorkbench']
}) {
  const [localName, setLocalName] = useState<string>(name ?? '')
  const [localDescription, setLocalDescription] = useState<string>(description ?? '')

  const onValidityChange = () => {}
  const [result, runCheck] = useCheckName(onValidityChange)

  const [loading, setLoading] = useState(false)
  const [errorMessages, setErrorMessages] = useState<Record<string, string | undefined>>({})

  const readOnly = useReadOnly()

  useEffect(() => {
    setLocalName(name)
  }, [name])

  useEffect(() => {
    setLocalDescription(description)
  }, [description])

  const handleSubmit = async (e?: React.FormEvent<HTMLFormElement>) => {
    e?.preventDefault()

    if (!localName) {
      setErrorMessages(errors => ({...errors, name: 'Name is required'}))
      return
    }
    // Button may still be clickable even if it looks disabled so check!
    if (buttonDisabled) {
      return
    }

    setLoading(true)
    await updatePartialWorkbench({name: localName, description: localDescription, friendlyName: result.generatedName})
    setLoading(false)
  }

  const handleNameChange = (newName: string) => {
    setLocalName(newName)
    setErrorMessages(errors => ({...errors, name: undefined}))
  }

  const inputDisabled = readOnly || isFetching || previousRefinements.length === 0
  const buttonDisabled =
    readOnly ||
    isFetching ||
    previousRefinements.length === 0 ||
    (localName === name && localDescription === description) ||
    isError(result)

  return (
    <ScopedCommands commands={{'github:submit-form': () => handleSubmit()}}>
      <form onSubmit={handleSubmit}>
        <Stack>
          <NameInput
            sparkName={localName}
            onChange={handleNameChange}
            onValidityChange={onValidityChange}
            result={result}
            runCheck={runCheck}
            disabled={inputDisabled}
          />

          <FormControl disabled={inputDisabled}>
            <FormControl.Label>Description</FormControl.Label>
            <Textarea
              block
              rows={3}
              name="description"
              aria-label="Description"
              value={localDescription}
              placeholder="Enter description"
              onChange={e => {
                setLocalDescription(e.target.value)
                setErrorMessages(errors => ({...errors, description: undefined}))
              }}
            />
            <FormControl.Caption>Generated by Spark</FormControl.Caption>
            {errorMessages.description && (
              <FormControl.Validation variant="error">
                <span>{errorMessages.description}</span>
              </FormControl.Validation>
            )}
          </FormControl>
          <div>
            <Button
              type="submit"
              variant="primary"
              inactive={buttonDisabled && !readOnly}
              disabled={readOnly}
              loading={loading}
            >
              Save changes
            </Button>
          </div>
        </Stack>
      </form>
    </ScopedCommands>
  )
}

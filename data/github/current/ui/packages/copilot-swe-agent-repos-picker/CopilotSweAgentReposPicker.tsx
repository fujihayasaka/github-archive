import {ControlGroup} from '@github-ui/control-group'
import type {PickerRepository} from '@github-ui/repos-picker'
import {modes} from '@github-ui/repos-picker/modes'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {Banner} from '@primer/react/experimental'
import {useState} from 'react'

type SelectionMode = 'no_repos' | 'all_repos' | 'multiple'
export interface CopilotSweAgentReposPickerProps {
  modeChangedCallbackPath: string
  selectionsChangedCallbackPath: string
  projectDisplayName: string
  userLogin: string
  selection: PickerRepository[]
  mode: SelectionMode
}

export function CopilotSweAgentReposPicker(props: CopilotSweAgentReposPickerProps) {
  const [mode, setMode] = useState<SelectionMode>(props.mode)
  const [selected, setSelected] = useState<PickerRepository[]>(props.selection)
  const [isPolicyBannerShown, setIsPolicyBannerShown] = useState<boolean>(false)

  const onSelectionChange = async (repos: PickerRepository[]) => {
    // Clear the banner when the user tries to change the selection
    setIsPolicyBannerShown(false)

    // Store the original selection in case the request fails
    const originalSelection = selected

    try {
      setSelected(repos)
      await reactFetchJSON(props.selectionsChangedCallbackPath, {
        method: 'PUT',
        body: {
          selected_repos: repos.map(repo => repo.id),
        },
      })
    } catch {
      // If the request fails, show a banner to inform the user
      setIsPolicyBannerShown(true)

      // Revert to the original selection
      setSelected(originalSelection)
    }
  }

  const onModeChange = async (newMode: string) => {
    // Clear the banner when the user tries to change the selection
    setIsPolicyBannerShown(false)

    // Store the original mode in case the request fails
    const originalMode = mode

    try {
      const selectionMode = newMode as SelectionMode
      setMode(newMode as SelectionMode)
      await reactFetchJSON(props.modeChangedCallbackPath, {
        method: 'PUT',
        body: {
          mode: selectionMode,
        },
      })
    } catch {
      // If the request fails, show a banner to inform the user
      setIsPolicyBannerShown(true)

      // Revert to the original mode
      setMode(originalMode)
    }
  }

  const supportedModes = [
    {name: 'no_repos', label: 'No repositories'},
    {...modes.all, name: 'all_repos'},
    modes.buildMultiple({
      selected,
      onSubmit: onSelectionChange,
      scope: {type: 'organization', slug: props.userLogin},
    }),
  ]

  return (
    <>
      {isPolicyBannerShown && (
        <Banner
          variant="critical"
          title="Failed to save changes"
          hideTitle
          className="mb-3"
          onDismiss={() => {
            setIsPolicyBannerShown(false)
          }}
        >
          Failed to update selection, please try again later.
        </Banner>
      )}
      <ControlGroup className="borderColor-default px-1">
        <ControlGroup.Selector
          selectedMode={mode}
          onModeChange={onModeChange}
          modes={supportedModes}
          title="Repository access"
          description={`Choose which repositories ${props.projectDisplayName} should be enabled in. ${props.projectDisplayName} will only be available where it is enabled for the repository and in the Copilot license policies.`}
        />
      </ControlGroup>
    </>
  )
}

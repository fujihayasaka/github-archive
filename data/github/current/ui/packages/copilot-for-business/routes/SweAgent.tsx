import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {PickerRepository} from '@github-ui/repos-picker'
import {modes} from '@github-ui/repos-picker/modes'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {Banner} from '@primer/react/experimental'
import {Label, Link, Text} from '@primer/react'
import {useState} from 'react'
import type {CopilotSweAgentPayload, SelectionMode} from '../standalone/types'
import {PageHeading} from '../traditional/components/Ui'
import styles from './Policies.module.css'
import {ControlGroup} from '@github-ui/control-group'

export default function SweAgentPage() {
  const routeData = useRoutePayload<CopilotSweAgentPayload>()

  return (
    <>
      <PageHeading
        name={routeData.project_display_name}
        meta={
          <Label variant="success" className="ml-2">
            Preview
          </Label>
        }
      />
      {routeData.access_warning_banner_content && (
        <Banner variant="warning" title="No Copilot coding agent access" hideTitle className="mb-3">
          {routeData.access_warning_banner_content}
        </Banner>
      )}
      <div className={styles.topBox}>
        <span>
          With {routeData.project_display_name}, developers can delegate tasks to Copilot, freeing them to focus on the
          creative, complex, and high-impact work that matters most. Simply assign an issue to Copilot, wait for the
          agent to request review, then leave feedback on the pull request to iterate.{' '}
          <Link href="https://gh.io/copilot-coding-agent-docs" inline>
            Learn more in the docs.
          </Link>
        </span>
      </div>

      <div className="mt-4">
        <RepositoryAccessSelection />
      </div>

      <div className="mt-4">
        <Text as="p" sx={{color: 'fg.muted', mt: 4}}>
          Use of Copilot coding agent is subject to the{' '}
          <Link inline href="https://docs.github.com/en/site-policy/github-terms/github-pre-release-license-terms">
            pre-release terms
          </Link>
          .
        </Text>
      </div>
    </>
  )
}

function RepositoryAccessSelection() {
  const routeData = useRoutePayload<CopilotSweAgentPayload>()
  const [mode, setMode] = useState<SelectionMode>(routeData.mode)
  const [selected, setSelected] = useState<PickerRepository[]>(routeData.selection)
  const [isPolicyBannerShown, setIsPolicyBannerShown] = useState<boolean>(false)

  const onSelectionChange = async (repos: PickerRepository[]) => {
    // Clear the banner when the user tries to change the selection
    setIsPolicyBannerShown(false)

    // Store the original selection in case the request fails
    const originalSelection = selected

    try {
      setSelected(repos)
      await reactFetchJSON(routeData.selections_changed_callback_path, {
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
    // Clear the banner when the user tries to change the mode
    setIsPolicyBannerShown(false)

    // Store the original mode in case the request fails
    const originalMode = mode

    try {
      const selectionMode = newMode as SelectionMode
      setMode(newMode as SelectionMode)
      await reactFetchJSON(routeData.mode_changed_callback_path, {
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
      scope: {type: 'organization', slug: routeData.org_login},
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
          selectorIcon={undefined}
          selectedMode={mode}
          onModeChange={onModeChange}
          modes={supportedModes}
          title="Repository access"
          description={`Choose which repositories ${routeData.project_display_name} should be enabled in. To be able to assign an issue to Copilot, the user must have have access to ${routeData.project_display_name} and it must be enabled for the repository.`}
        />
      </ControlGroup>
    </>
  )
}

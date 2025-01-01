import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {RoutePayload} from './types'
import {Box} from '@primer/react'
import {Header} from '../../components/Header'
import {useNavigateWithFlashBanner} from '../../features/NavigateWithFlashBanner'
import {TrainingForm, useForm} from '../../features/TrainingForm'
import {useOrgOnlyRepos} from '../../features/RepoPicker'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {RouteProviders} from '../../context/RouteProviders'
import {useQueryInitialSelected} from './hooks/use-query-initial-selected'

export function Edit() {
  return (
    <RouteProviders>
      <Component />
    </RouteProviders>
  )
}

function Component() {
  const {
    availableLanguages,
    canCollectPrivateTelemetry,
    createPath,
    languages: initialLanguages,
    organization: org,
    pipelineId,
    policyPath,
    repoCount: initialRepoCount,
    repoListPath,
    showPath,
    wasPrivateTelemetryCollected,
  } = useRoutePayload<RoutePayload>()
  const {navigate} = useNavigateWithFlashBanner()
  const showPrivateTelemetryToggle = useFeatureFlag('copilot_private_telemetry_access')

  const {formErrors, handleSubmit, isSubmitting} = useForm({createPath, pipelineId})
  const repoPickerQueryFn = useOrgOnlyRepos({org})

  const handleCancel = () => navigate(showPath)

  const {fetchSelected, initialSelectedRepos, isLoadingSelected} = useQueryInitialSelected({repoListPath})

  const handleFetchSelected = (): void => {
    if (initialSelectedRepos) return
    fetchSelected()
  }

  return (
    <Box sx={{display: 'flex', flexDirection: 'column', gap: '16px'}}>
      <Header
        subtext="Update your custom model by including repositories and data that is reflective of your commonly used
          programming languages, internal frameworks, and libraries. Settings shown reflect the previous model settings."
        text="Retrain custom model"
      />

      <TrainingForm
        availableLanguages={availableLanguages}
        canCollectPrivateTelemetry={canCollectPrivateTelemetry}
        fetchSelected={handleFetchSelected}
        formErrors={formErrors}
        initialLanguages={initialLanguages}
        initialRepoCount={initialRepoCount}
        initialSelectedRepos={initialSelectedRepos}
        isEditing
        isLoadingSelected={isLoadingSelected}
        isSubmitting={isSubmitting}
        onCancel={handleCancel}
        onSubmit={handleSubmit}
        org={org}
        policyPath={policyPath}
        repoPickerQueryFn={repoPickerQueryFn}
        showPrivateTelemetryToggle={showPrivateTelemetryToggle}
        wasPrivateTelemetryCollected={wasPrivateTelemetryCollected}
      />
    </Box>
  )
}

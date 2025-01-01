import {Box, Flash} from '@primer/react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {RoutePayload} from './types'
import {Header} from '../../components/Header'
import {useOrgOnlyRepos} from '../../features/RepoPicker'
import {TrainingForm, useForm} from '../../features/TrainingForm'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {RouteProviders} from '../../context/RouteProviders'

export function New() {
  return (
    <RouteProviders>
      <Component />
    </RouteProviders>
  )
}

function Component() {
  const {
    adminEmail,
    availableLanguages,
    canCollectPrivateTelemetry,
    createPath,
    enoughDataToTrain,
    organization: org,
    policyPath,
  } = useRoutePayload<RoutePayload>()
  const {formErrors, handleSubmit, isSubmitting} = useForm({createPath})
  const repoPickerQueryFn = useOrgOnlyRepos({org})
  const showPrivateTelemetryToggle = useFeatureFlag('copilot_private_telemetry_access')

  return (
    <Box sx={{display: 'flex', flexDirection: 'column', gap: '16px'}}>
      <Header
        subtext={
          enoughDataToTrain
            ? 'Train your custom model by including repositories and data that is reflective of your commonly used programming languages, internal frameworks, and libraries.'
            : undefined
        }
        text="New custom model"
      />

      {enoughDataToTrain ? (
        <TrainingForm
          adminEmail={adminEmail}
          availableLanguages={availableLanguages}
          canCollectPrivateTelemetry={canCollectPrivateTelemetry}
          formErrors={formErrors}
          isSubmitting={isSubmitting}
          onSubmit={handleSubmit}
          org={org}
          policyPath={policyPath}
          repoPickerQueryFn={repoPickerQueryFn}
          showPrivateTelemetryToggle={showPrivateTelemetryToggle}
        />
      ) : (
        <Flash>Sorry, you do not have enough repository data in your org to train a model.</Flash>
      )}
    </Box>
  )
}

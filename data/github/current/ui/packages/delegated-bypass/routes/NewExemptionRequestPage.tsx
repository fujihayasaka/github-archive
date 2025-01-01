import type {FC} from 'react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {componentRegistry, RequestForm} from '../components/RequestForm/index'
import type {NewExemptionRequestPayload} from '../delegated-bypass-types'
import {ExemptionRequestContainer} from '../components/ExemptionRequestContainer'
import {useRequestTypeContext} from '../contexts/RequestTypeContext'
import {RequestFormProvider} from '../contexts/RequestFormContext'

export const NewExemptionRequestPage: FC = () => {
  const {ruleSuite, hasPostApprovalAction} = useRoutePayload<NewExemptionRequestPayload>()
  const requestType = useRequestTypeContext()

  const {displayName, FormControls, instructions, violations} = componentRegistry({requestType, hasPostApprovalAction})

  let rulesetId = undefined
  const uniqueRulesetIds = [...new Set(ruleSuite.ruleRuns.map(r => r?.rulesetId))]
  if (uniqueRulesetIds.length === 1) {
    rulesetId = uniqueRulesetIds[0]
  }

  return (
    <ExemptionRequestContainer
      ruleSuite={ruleSuite}
      displayName={displayName}
      violations={violations}
      requestType={requestType}
    >
      <RequestFormProvider readOnly={false}>
        <RequestForm instructions={instructions} rulesetId={rulesetId}>
          {FormControls ? <FormControls /> : null}
        </RequestForm>
      </RequestFormProvider>
    </ExemptionRequestContainer>
  )
}

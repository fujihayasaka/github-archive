import {useId} from 'react'
import {AiModelIcon, AlertIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Heading, Link, Spinner} from '@primer/react'
import styles from './ModelsGlobalAccessToggle.module.css'
import {useOrganizationAccessPolicy} from '../contexts/OrganizationAccessPolicyContext'
import {disableOrgModelsPayload, enableOrgModelsPayload} from '../hooks/use-update-organization-access-policy'

export function ModelsGlobalAccessToggle() {
  const {didUpdateError, isModelsEnabled, updateOrganizationAccessPolicy, isUpdatePending} =
    useOrganizationAccessPolicy()
  const errorMessageId = useId()

  return (
    <div className={styles.container}>
      <Heading as="h3" variant="small" className="mb-2">
        <AiModelIcon className="v-align-middle mr-2" />
        Models in your organization
      </Heading>
      <p className="fgColor-muted">
        Enable GitHub Models for your organization to allow users to interact with models using their code. This suite
        of AI development features is available at the repository level.{' '}
        <Link href="https://gh.io/models-org-learn-more" inline>
          Learn more about Models.
        </Link>
      </p>
      <div className="d-md-flex flex-items-center">
        <ActionMenu>
          <ActionMenu.Button
            disabled={isUpdatePending}
            aria-describedby={didUpdateError ? errorMessageId : undefined}
            leadingVisual={() => {
              if (didUpdateError) return <AlertIcon />
              return isUpdatePending ? <Spinner size="small" /> : null
            }}
            className={didUpdateError ? 'mr-3' : undefined}
          >
            <span className="sr-only">Models status: </span>
            <span>{isModelsEnabled ? 'Enabled' : 'Disabled'}</span>
          </ActionMenu.Button>
          <ActionMenu.Overlay>
            {!isUpdatePending && (
              <ActionList selectionVariant="single">
                <ActionList.Item
                  selected={isModelsEnabled}
                  onSelect={() => updateOrganizationAccessPolicy(enableOrgModelsPayload())}
                >
                  Enabled
                </ActionList.Item>
                <ActionList.Item
                  selected={!isModelsEnabled}
                  onSelect={() => updateOrganizationAccessPolicy(disableOrgModelsPayload())}
                >
                  Disabled
                </ActionList.Item>
              </ActionList>
            )}
          </ActionMenu.Overlay>
        </ActionMenu>
        {didUpdateError && (
          <div id={errorMessageId} className="fgColor-danger">
            There was a problem saving your policy. Please try again later.
          </div>
        )}
      </div>
    </div>
  )
}

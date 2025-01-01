import {useId} from 'react'
import {AiModelIcon, AlertIcon, ShieldLockIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Heading, Link, Spinner} from '@primer/react'
import styles from './ModelsAccessToggle.module.css'
import {useAccessPolicy} from '../contexts/AccessPolicyContext'
import type {RepositoryAccessPolicyShowPayload} from '../types'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {disableRepoModelsPayload, enableRepoModelsPayload} from '../hooks/use-update-repository-access-policy'

export function ModelsAccessToggle() {
  const {isAccessConfigurable, repositoryOwnerType} = useRoutePayload<RepositoryAccessPolicyShowPayload>()

  const {isRepoModelsEnabled, updateRepositoryAccessPolicy, isUpdatePending, didUpdateError} = useAccessPolicy()
  const errorMessageId = useId()

  return (
    <div className={styles.container}>
      <Heading as="h3" variant="small" className="mb-2">
        <AiModelIcon className="v-align-middle mr-2" />
        Models in this repository
      </Heading>
      <p className="fgColor-muted">
        If disabled, the Models tab will be hidden, and the prompt editor and comparison tooling evaluations will be
        unavailable.
        <span>
          {repositoryOwnerType === 'organization'
            ? ' For additional configuration options, go to models in organization settings. '
            : ' '}
        </span>
        <Link href="https://gh.io/models-org-learn-more" inline>
          Learn more about Models.
        </Link>
      </p>
      {isAccessConfigurable ? (
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
              <span>{isRepoModelsEnabled ? 'Enabled' : 'Disabled'}</span>
            </ActionMenu.Button>
            <ActionMenu.Overlay>
              {!isUpdatePending && (
                <ActionList selectionVariant="single">
                  <ActionList.Item
                    selected={isRepoModelsEnabled}
                    onSelect={() => updateRepositoryAccessPolicy(enableRepoModelsPayload())}
                  >
                    Enabled
                  </ActionList.Item>
                  <ActionList.Item
                    selected={!isRepoModelsEnabled}
                    onSelect={() => updateRepositoryAccessPolicy(disableRepoModelsPayload())}
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
      ) : (
        <div>
          <ShieldLockIcon className="v-align-middle mr-1" />
          This setting has been disabled by organization policy administrators.
        </div>
      )}
    </div>
  )
}

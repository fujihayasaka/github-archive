import {ResponseError} from '@github-ui/react-core/future/response-error'
import {useQueriesConfig, useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {type QueryKey, useMutation, useQuery, useQueryClient, type UseQueryOptions} from '@github-ui/react-query'
import {reactFetch} from '@github-ui/verified-fetch'
import {Button, FormControl, Heading, Stack, TextInput} from '@primer/react'
import {Banner} from '@primer/react/experimental'

import ExampleHeader from '../components/ExampleHeader'
import type {UserStatus} from '../data-types'
import {reactCoreExamplesMutationsRoute} from './mutations-route'
import {reactCoreExamplesSharedComponentsRoute} from './shared-components-route'

export function SharedComponents() {
  const {
    data: {userStatus},
    queryKey,
  } = useRouteQuery(reactCoreExamplesSharedComponentsRoute, 'mainQuery')
  const sharedComponentQueryOptions = useQueriesConfig(reactCoreExamplesSharedComponentsRoute, 'mainQuery')

  const {statusMutation, handleUpdateStatus} = useStatusMutation(queryKey)

  return (
    <>
      <ExampleHeader pageTitle="SharedComponents" docsUrl={docsUrl} />
      <Stack justify="space-between" gap="spacious" direction={{wide: 'horizontal'}}>
        <Stack.Item grow>
          <Stack data-testid="sharedComponent">
            <Heading as="h4" variant="small">
              Shared Component
            </Heading>
            <SharedComponent
              userStatus={userStatus}
              onUpdateStatus={handleUpdateStatus}
              isError={statusMutation.isError}
              isPending={statusMutation.isPending}
            />
            <Banner
              title="Preferred Pattern"
              description={
                <>
                  This version is the preferred shared component pattern: the component takes data as props and executes
                  mutations passed via callback prop. There is no network access within the component itself.
                </>
              }
            />
          </Stack>
        </Stack.Item>
        <Stack.Item grow>
          <Stack data-testid="sharedComponentQuery">
            <Heading as="h4" variant="small">
              Shared Component with Query
            </Heading>
            <SharedComponentWithQuery statusQuery={sharedComponentQueryOptions.queryConfig} />
            <Banner
              variant="warning"
              title="Undesirable Pattern"
              description={
                <>
                  <p>
                    This version receives a <code>QueryOptions</code> object passed as a prop so that it can optimize
                    access the the query data.
                  </p>
                  <p>
                    <b>
                      This pattern introduces complexity, coupling and indirection that is unnecessary in almost all
                      cases;
                    </b>
                    it is a performance optimization and should not be used unless there&apos;s is an observed
                    performance issue.{' '}
                    <a href={docsUrl} target="_blank" rel="noreferrer">
                      Consult the docs
                    </a>{' '}
                    for a discussion of when this kind of optimization might be useful.
                  </p>
                </>
              }
            />
          </Stack>
        </Stack.Item>
      </Stack>
    </>
  )
}

/**
 * This component is a shared component that takes props and executes a mutation passed via callback prop
 * It is the preferred pattern for shared components. It does not have any network access within the component itself.
 */
function SharedComponent({
  userStatus,
  onUpdateStatus,
  isError,
  isPending,
}: {
  userStatus?: UserStatus
  onUpdateStatus: (e: React.FormEvent<HTMLFormElement>) => void
  isError?: boolean
  isPending: boolean
}) {
  return (
    <form onSubmit={onUpdateStatus} data-testid="userStatus-form">
      <Stack gap="normal">
        <FormControl>
          <FormControl.Label>Set status</FormControl.Label>
          <TextInput name="message" defaultValue={userStatus?.message ?? ''} key={userStatus?.message} />
          <FormControl.Caption>Careful! This will really update your status!</FormControl.Caption>
          {isError ? (
            <FormControl.Validation variant="error" data-testid="status-error">
              Failed to update status
            </FormControl.Validation>
          ) : null}
        </FormControl>
        <Button type="submit" loading={isPending}>
          Set Status
        </Button>
      </Stack>
    </form>
  )
}

/**
 * This is a less-desirable shared component pattern that can provide a performance optimization in some cases by
 * moving query-data access lower in the render tree: avoiding unnecessary re-renders higher in the tree.
 * It is a performance optimization and should not be used unless there is an observed performance issue.
 * The component takes a queryOptions prop and uses it to access the query data.
 */
function SharedComponentWithQuery({statusQuery}: {statusQuery: UseQueryOptions}) {
  const {data: userStatus} = useQuery({
    ...(statusQuery as UseQueryOptions<{payload: {userStatus: UserStatus}}>),
    select: d => d.payload.userStatus,
    notifyOnChangeProps: ['data'],
  })

  const {statusMutation, handleUpdateStatus} = useStatusMutation(statusQuery.queryKey)

  return (
    <SharedComponent
      userStatus={userStatus}
      onUpdateStatus={handleUpdateStatus}
      isError={statusMutation.isError}
      isPending={statusMutation.isPending}
    />
  )
}

function useStatusMutation(queryKey: QueryKey) {
  const queryClient = useQueryClient()

  const statusMutation = useMutation({
    mutationFn: updateStatus,
    onSuccess: () => {
      queryClient.invalidateQueries({queryKey})
    },
  })

  function handleUpdateStatus(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const formData = new FormData(e.currentTarget)
    statusMutation.mutate(formData)
  }

  return {statusMutation, handleUpdateStatus}
}

async function updateStatus(status: FormData) {
  const path = reactCoreExamplesMutationsRoute.generatePath({})
  const init = {
    method: 'PUT',
    body: status,
  }
  const response = await reactFetch(path, init)
  if (!response.ok) {
    throw new ResponseError('Failed to update status', response)
  }
  return response.json()
}

const docsUrl =
  'https://github.com/github/github/blob/master/ui/packages/react-core/future/docs/data-router/recipes/shared-components.md'

import {ResponseError} from '@github-ui/react-core/future/response-error'
import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {useMutation, useQueryClient} from '@github-ui/react-query'
import {reactFetch} from '@github-ui/verified-fetch'
import {Button, FormControl, Stack, TextInput} from '@primer/react'

import ExampleHeader from '../components/ExampleHeader'
import {reactCoreExamplesMutationsRoute} from './mutations-route'

export function Mutations() {
  const {data, queryKey} = useRouteQuery(reactCoreExamplesMutationsRoute, 'mainQuery')
  const queryClient = useQueryClient()

  const statusMutation = useMutation({
    mutationFn: updateStatus,
    onSuccess: () => {
      queryClient.invalidateQueries({queryKey})
    },
  })
  function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const formData = new FormData(e.currentTarget)
    statusMutation.mutate(formData)
  }

  return (
    <>
      <ExampleHeader
        pageTitle="Mutations"
        docsUrl="https://github.com/github/github/blob/master/ui/packages/react-core/future/docs/data-router/recipes/mutations.md"
      />

      <p data-testid="status">Your status is: {data.userStatus?.message ?? <span>--</span>}</p>

      <form onSubmit={handleSubmit} data-testid="userStatus-form">
        <Stack gap="normal">
          <FormControl>
            <FormControl.Label>Set status</FormControl.Label>
            <TextInput name="message" defaultValue={data.userStatus?.message ?? ''} />
            <FormControl.Caption>Careful! This will really update your status!</FormControl.Caption>
            {statusMutation.isError ? (
              <FormControl.Validation variant="error" data-testid="status-error">
                Failed to update status
              </FormControl.Validation>
            ) : null}
          </FormControl>
          <Button type="submit" loading={statusMutation.isPending}>
            Set Status
          </Button>
        </Stack>
      </form>
    </>
  )
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

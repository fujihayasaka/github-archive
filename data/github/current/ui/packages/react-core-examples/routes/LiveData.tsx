import {LabelsList} from '@github-ui/labels-list'
import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {useAlive} from '@github-ui/use-alive'
import {Heading, Stack} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {Link} from 'react-router-dom'

import ExampleHeader from '../components/ExampleHeader'
import {reactCoreExamplesLiveDataRoute} from './live-data-route'

export function LiveData() {
  const {
    data: {aliveChannel, pull},
    refetch,
  } = useRouteQuery(reactCoreExamplesLiveDataRoute, 'mainQuery')

  useAlive(aliveChannel, refetch)

  return (
    <>
      <ExampleHeader
        pageTitle="Live Data"
        docsUrl="https://github.com/github/github/blob/master/ui/packages/react-core/future/docs/data-router/recipes/live-data.md"
      />

      <Stack direction="horizontal" align="center" padding="normal" className="border rounded-2">
        <Stack.Item grow>
          <Heading as="h3" variant="small">
            <Link to={pull.url}>{pull.title}</Link>
          </Heading>
        </Stack.Item>

        <Stack.Item>
          <LabelsList labels={pull.labels} />
        </Stack.Item>
      </Stack>

      <Banner
        title="Instructions"
        description={
          <>
            To see the data update live,{' '}
            <Link to={pull.url} target="_blank">
              open the above pull-request in another window.
            </Link>{' '}
            Make changes to the title or labels in that window and observe those changes updating here.
          </>
        }
      />
    </>
  )
}

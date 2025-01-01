import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {GroupForm} from '../components/GroupForm'
import {GroupFormProvider} from '../contexts/GroupFormContext'
import {Layout} from '../components/Layout'
import type {ShowPayload} from '../types'

export function Show() {
  const {group} = useRoutePayload<ShowPayload>()
  const name = group.group_path.split('/').pop()

  return (
    <Layout page={'Show'} name={name}>
      <GroupFormProvider>
        <GroupForm group={group} page={'Show'} />
      </GroupFormProvider>
    </Layout>
  )
}

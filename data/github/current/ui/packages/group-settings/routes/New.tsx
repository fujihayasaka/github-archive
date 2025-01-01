import {GroupForm} from '../components/GroupForm'
import {Layout} from '../components/Layout'
import {GroupFormProvider} from '../contexts/GroupFormContext'

export function New() {
  return (
    <Layout page={'New'}>
      <GroupFormProvider>
        <GroupForm page={'New'} />
      </GroupFormProvider>
    </Layout>
  )
}

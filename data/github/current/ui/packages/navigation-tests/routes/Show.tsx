import {useRouteParams} from '@github-ui/react-core/future/use-route-params'
import {showRoute} from './show-route'
import {DisplayData} from '../components/DisplayData'

export function Show() {
  const {id} = useRouteParams(showRoute)

  return (
    <>
      <p data-hpc>Show {id}</p>
      <DisplayData route={showRoute} />
    </>
  )
}

import {AlertFillIcon} from '@primer/octicons-react'
import {MODELS_ROUTE, MODELS_ROUTE_ENT, MODELS_ROUTE_ORG} from '../../routes'
import useRoute from '../../hooks/use-route'
import {Link} from '@primer/react'
import {useContext} from 'react'
import {PageContext} from '../../App'

export const ModelsBillingErrorMessage = () => {
  const {isOrganizationRoute, isEnterpriseRoute} = useContext(PageContext)
  const {path: modelsRoute} = useRoute(
    isEnterpriseRoute ? MODELS_ROUTE_ENT : isOrganizationRoute ? MODELS_ROUTE_ORG : MODELS_ROUTE,
  )
  return (
    <div className="mt-2 fgColor-attention">
      <AlertFillIcon className="mr-1" />
      Enable billing to set a budget. See{' '}
      <Link inline href={modelsRoute} className="fgColor-attention">
        Models policy configuration
      </Link>
      .
    </div>
  )
}

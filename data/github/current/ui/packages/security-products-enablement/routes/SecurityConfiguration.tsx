import type React from 'react'
import {useState} from 'react'
import {Link} from '@github-ui/react-core/link'
import {useAlive} from '@github-ui/use-alive'
import {useDebounce} from '@github-ui/use-debounce'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Link as PrimerLink, Flash} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {
  settingsOrgSecurityProductsPath,
  settingsBusinessSecurityAnalysisPath,
  settingsUserSecurityProductsPath,
} from '@github-ui/paths'
import {RenderContext, type FlashParams, type SecurityConfigurationPayload} from '../security-products-enablement-types'
import {useAppContext} from '../contexts/AppContext'
import Banner from '../components/Banner'
import Subhead from '../components/Subhead'
import {fetchInProgressStatus} from '../utils/api-helpers'
import {getIcon, isShowOnly} from '../utils/helpers'
import Form from '../components/SecurityConfiguration/Form'

import styles from './SecurityConfiguration.module.css'
import {clsx} from 'clsx'

const SecurityConfiguration: React.FC = () => {
  const payload = useRoutePayload<SecurityConfigurationPayload>()
  const {organization, enterprise, renderContext} = useAppContext()
  const owner = renderContext === RenderContext.Organization ? organization : enterprise?.slug
  const isNew = !payload.securityConfiguration
  const isShow = isShowOnly(payload.securityConfiguration, renderContext)
  const [flashMessage, setFlashMessage] = useState<FlashParams>({})
  const channel = payload.channel

  const [changesInProgress, setChangesInProgress] = useState(payload.changesInProgress)
  const debouncedUpdateChangesInProgress = useDebounce(async () => {
    const response = await fetchInProgressStatus(owner!)
    if (response) setChangesInProgress(response)
  }, 1500)
  const handleAliveEvent = () => debouncedUpdateChangesInProgress()
  useAlive(channel, handleAliveEvent)

  const inProgressText = `Another enablement event is in progress. Modifying or deleting this configuration is not available until it's finished.`

  let breadcrumbContextLink = ''
  let breadcrumbContextText = ''

  switch (renderContext) {
    case RenderContext.Enterprise:
      breadcrumbContextLink = settingsBusinessSecurityAnalysisPath({business: owner!})
      breadcrumbContextText = 'Advanced Security'
      break
    case RenderContext.Organization:
      breadcrumbContextLink = settingsOrgSecurityProductsPath({org: organization})
      breadcrumbContextText = 'Advanced Security'
      break
    case RenderContext.User:
      breadcrumbContextLink = settingsUserSecurityProductsPath()
      breadcrumbContextText = 'Code security configurations'
      break
  }

  const securityConfigurationTitle = isShow ? 'View configuration' : isNew ? 'New configuration' : 'Edit configuration'

  return (
    <>
      <div className={styles.Box}>
        <PrimerLink as={Link} to={breadcrumbContextLink}>
          {breadcrumbContextText}
        </PrimerLink>
        {' / '}
        {securityConfigurationTitle}
      </div>
      <Subhead>
        <div className={styles.Box_1}>
          <h2 data-testid="form-title" className={clsx('h1-override-shared-component', styles.Text)}>
            {securityConfigurationTitle}
          </h2>
        </div>
      </Subhead>
      {/* FIXME: Determine if we really need to worry about in progress events at the user level */}
      {!isNew && renderContext !== RenderContext.User && changesInProgress.inProgress && (
        <Banner bannerText={inProgressText} />
      )}
      {flashMessage.message && (
        <Flash variant={flashMessage.variant}>
          <Octicon icon={getIcon(flashMessage.variant)} />
          {flashMessage.message}
        </Flash>
      )}
      <Form setFlashMessage={setFlashMessage} />
    </>
  )
}

export default SecurityConfiguration

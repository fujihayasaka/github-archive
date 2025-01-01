import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {FlexTemplate} from '@github-ui/swp-core/layouts/contentful/FlexTemplate'
import resolveResponse from 'contentful-resolve-response'
import {FreeFormTemplate, Universe23WaitlistTemplate, ContactSalesTemplate} from '../layouts'
import {F2Template} from '../layouts/F2Template'
import {toContainerPage, toEntryCollection, type ContainerPage} from '../lib/types/contentful'
import {toPayload} from '../lib/types/payload'

function getReactComponentFor<Page extends ContainerPage>(page: Page): React.ElementType {
  const map: Record<ContainerPage['fields']['template']['sys']['contentType']['sys']['id'], React.ElementType> = {
    templateF2: F2Template,
    templateFlex: FlexTemplate,
    templateFreeForm: FreeFormTemplate,
    templateUniverse23Waitlist: Universe23WaitlistTemplate,
    templateContactSalesForm: ContactSalesTemplate,
  }

  return map[page.fields.template.sys.contentType.sys.id]
}

export const ShowPage = () => {
  const {contentfulRawJsonResponse, userLoggedIn, octocaptchaHost} = toPayload(useRoutePayload<unknown>())
  const page = toContainerPage(toEntryCollection(resolveResponse(contentfulRawJsonResponse)).at(0))

  const PageComponent = getReactComponentFor(page)

  return <PageComponent page={page} userLoggedIn={userLoggedIn} octocaptchaHost={octocaptchaHost} />
}

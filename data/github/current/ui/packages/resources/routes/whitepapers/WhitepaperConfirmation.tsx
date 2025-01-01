import resolveResponse from 'contentful-resolve-response'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Grid, Section, SectionIntro} from '@primer/react-brand'
import {toWhitepaperPage, toEntryCollection} from '../../lib/types/contentful'
import {toPayload} from '../../lib/types/payload'

export function WhitepapersConfirmation() {
  const {contentfulRawJsonResponse} = toPayload(useRoutePayload<unknown>())
  const page = toWhitepaperPage(toEntryCollection(resolveResponse(contentfulRawJsonResponse)).at(0))

  return (
    <Grid>
      <Grid.Column>
        <Section backgroundColor="subtle" rounded>
          <SectionIntro align="center">
            <SectionIntro.Heading size="3">{page.fields.title}</SectionIntro.Heading>
          </SectionIntro>
        </Section>
      </Grid.Column>
    </Grid>
  )
}

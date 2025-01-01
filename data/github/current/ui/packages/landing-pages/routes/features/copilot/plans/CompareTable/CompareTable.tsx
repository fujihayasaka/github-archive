import {useContext} from 'react'

import {Grid, Stack} from '@primer/react-brand'

import {getSectionContentById} from '../../../../../brand/lib/types/contentful'
import type {GenericContent, GenericSection} from '../../../../../brand/lib/types/contentful'

import {PlanTypeContext} from '../../_context/PlanTypeContext'

import {CompareTableGroup} from './CompareTableGroup'
import {CompareTableHeader} from './CompareTableHeader'

type Props = {
  contentfulContent: GenericSection
}

export function CompareTable(props: Props) {
  const {contentfulContent} = props
  const {planType} = useContext(PlanTypeContext)

  const tableHeader = getSectionContentById({
    content: contentfulContent.fields.content,
    id: 'featuresCopilotPlansComparisonHeader',
  }) as GenericContent

  const featureGroups = getSectionContentById({
    content: contentfulContent.fields.content,
    id: 'featuresCopilotPlansComparisonGroups',
  })?.fields.content as GenericContent[]

  return (
    <section id="compare" className="my-8">
      <Grid className="lp-Section-container--centerUntilMedium lp-Grid--noRowGap js-toggler-container">
        <Grid.Column span={12}>
          <div role="table" className="lp-Pricing-table" id={tableHeader?.fields.htmlId}>
            {tableHeader ? <CompareTableHeader contentfulContent={tableHeader} planType={planType} /> : null}

            <Stack direction="vertical" gap={32} padding="none">
              {featureGroups
                ? featureGroups.map(group => {
                    const {sys, fields} = group
                    const {heading, content} = fields

                    return <CompareTableGroup key={sys.id} heading={heading!} rows={content!} planType={planType} />
                  })
                : null}
            </Stack>
          </div>
        </Grid.Column>
      </Grid>
    </section>
  )
}

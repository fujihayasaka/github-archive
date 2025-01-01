import {PageHeader} from '@primer/react'
import {ModelsRepoLayout} from '../../components/ModelsRepoLayout'

export function ModelsRoute() {
  return (
    <ModelsRepoLayout>
      <PageHeader aria-label="Overview">
        <PageHeader.TitleArea>
          <PageHeader.Title>Overview</PageHeader.Title>
        </PageHeader.TitleArea>
      </PageHeader>
      Getting started
    </ModelsRepoLayout>
  )
}

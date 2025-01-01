import {PageLayout} from '@primer/react'
import {SessionHeader} from '../components/SessionHeader'
import {SessionContent} from '../components/SessionContent'
import {SessionPane} from '../components/SessionPane'

export function ShowSession() {
  return (
    <PageLayout containerWidth="full">
      <PageLayout.Header>
        <SessionHeader />
      </PageLayout.Header>
      <PageLayout.Pane position="start">
        <SessionPane />
      </PageLayout.Pane>
      <PageLayout.Content as="div">
        <SessionContent />
      </PageLayout.Content>
    </PageLayout>
  )
}

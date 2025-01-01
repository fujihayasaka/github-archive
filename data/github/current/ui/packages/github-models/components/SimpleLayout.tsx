import {PageLayout} from '@primer/react'
import type {PropsWithChildren} from 'react'

export function SimpleLayout({children}: PropsWithChildren) {
  return (
    <PageLayout columnGap="normal" padding="condensed" containerWidth="full">
      <PageLayout.Content as="div" width="full">
        {children}
      </PageLayout.Content>
    </PageLayout>
  )
}

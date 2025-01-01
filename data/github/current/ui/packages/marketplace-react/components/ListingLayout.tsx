import {PageLayout, Stack} from '@primer/react'
import styles from '../marketplace.module.css'

interface ListingLayoutProps {
  header: React.ReactNode
  body: React.ReactNode
  sidebar: React.ReactNode
}

export const ListingLayout = (props: ListingLayoutProps) => {
  const {header, body, sidebar} = props

  return (
    <div className="d-flex flex-column" data-testid={'marketplace-listing'} data-hpc>
      <PageLayout columnGap="normal">
        <PageLayout.Header>{header}</PageLayout.Header>

        <Stack justify="end" direction={{narrow: 'vertical', regular: 'horizontal'}} gap="none" className="width-full">
          <PageLayout.Content as="div">{body}</PageLayout.Content>
          <PageLayout.Pane hidden={{narrow: true, regular: false}} className={styles['marketplace-sidebar__pane']}>
            <Stack gap={'spacious'} className={styles['marketplace-sidebar__content-wrapper']}>
              {sidebar}
            </Stack>
          </PageLayout.Pane>
        </Stack>
      </PageLayout>
    </div>
  )
}

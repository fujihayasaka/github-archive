import {IconButton, PageLayout, ActionMenu, ActionList, Button, Heading} from '@primer/react'
import {Dialog} from '@primer/react/experimental'

import {KebabHorizontalIcon, TagIcon, MilestoneIcon} from '@primer/octicons-react'
import {useState} from 'react'

import SidebarNavigation from './SidebarNavigation'
import GlobalNavigation from './GlobalNavigation'
import MobileTitleNavigationButton from './MobileTitleNavigationButton'
import Filter from './Filter'

import styles from './Application.module.css'

const COLLECTION_TITLE = 'Issues'
const PAGE_TITLE = 'Assigned to you'

export function Application() {
  return (
    <div className={styles.Box}>
      <GlobalNavigation />
      <PageLayout containerWidth="full" padding="none" rowGap="none" columnGap="none">
        <PageLayout.Pane
          padding="none"
          position="start"
          divider="line"
          hidden={{
            narrow: true,
            regular: false,
            wide: false,
          }}
        >
          <div className={styles.Box_1}>
            <Heading as="h1" className={styles.Heading}>
              {COLLECTION_TITLE}
            </Heading>
            <div className={styles.Box_2}>
              <SidebarNavigation />
            </div>
          </div>
        </PageLayout.Pane>
        <PageLayout.Content padding="none" className={styles.PageLayout_Content}>
          <div className={styles.Box_3}>
            <div className={styles.Box_4}>
              <div className={styles.Box_5}>
                <div className={styles.Box_6}>
                  <MobileNavigationButton />
                </div>
                <Heading as="h2" className={styles.Heading_1}>
                  {PAGE_TITLE}
                </Heading>
              </div>
              <div className={styles.Box_7}>
                <Button variant="primary">New issue</Button>
                <ActionMenu>
                  <ActionMenu.Anchor>
                    {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
                    <IconButton unsafeDisableTooltip icon={KebabHorizontalIcon} aria-label="More" />
                  </ActionMenu.Anchor>
                  <ActionMenu.Overlay align="end">
                    <ActionList>
                      <ActionList.Item onSelect={() => alert('Workflows clicked')}>
                        Manage labels
                        <ActionList.LeadingVisual>
                          <TagIcon />
                        </ActionList.LeadingVisual>
                      </ActionList.Item>
                      <ActionList.Item onSelect={() => alert('Workflows clicked')}>
                        Manage milestones
                        <ActionList.LeadingVisual>
                          <MilestoneIcon />
                        </ActionList.LeadingVisual>
                      </ActionList.Item>
                    </ActionList>
                  </ActionMenu.Overlay>
                </ActionMenu>
              </div>
            </div>
            <div className={styles.Box_8}>
              <Filter />
              <div className={styles.Box_9}>Content</div>
            </div>
          </div>
        </PageLayout.Content>
      </PageLayout>
    </div>
  )
}

function MobileNavigationButton() {
  const [isOpen, setIsOpen] = useState(false)
  const onDialogClose = () => setIsOpen(false)
  return (
    <>
      <MobileTitleNavigationButton onClick={() => setIsOpen(!isOpen)}>{PAGE_TITLE}</MobileTitleNavigationButton>
      {isOpen && (
        <Dialog
          renderBody={() => (
            <div className={styles.Box_10}>
              <SidebarNavigation />
            </div>
          )}
          title={COLLECTION_TITLE}
          onClose={onDialogClose}
          position={{narrow: 'bottom'}}
        />
      )}
    </>
  )
}

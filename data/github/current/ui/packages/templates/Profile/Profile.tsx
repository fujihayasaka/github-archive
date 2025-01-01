// eslint-disable-next-line no-restricted-imports
import {PageLayout, Button, Link, Avatar, Heading} from '@primer/react'

import CustomReadme from './CustomReadme'
import PinnedRepositories from './PinnedRepositories'
import Navigation from './Navigation'
import Contributions from './Contributions'

import SidebarAchievements from './SidebarAchievements'
import SidebarSocialStats from './SidebarSocialStats'
import SidebarOrganizations from './SidebarOrganizations'
import SidebarSocialLinks from './SidebarSocialLinks'
import SidebarMatchingFollowers from './SidebarMatchingFollowers'

import styles from './Profile.module.css'

export function Profile() {
  return (
    <div className={styles.Box}>
      <Navigation />
      <PageLayout containerWidth="xlarge">
        <main className={styles.Box_1}>
          <PageLayout.Pane position="start">
            <div className={styles.Box_2}>
              <div className={styles.Box_3}>
                <Avatar src="https://avatars.githubusercontent.com/u/92997159?v=4" className={styles.Avatar_0} />
                <Heading as="h1" className={styles.Heading}>
                  Mona
                  <span className={styles.Text}>mona · she/her</span>
                </Heading>
              </div>

              <div className={styles.Box_4}>
                <Button>Follow</Button>
                <span>
                  Chief Purr-ogramming Mascot{' '}
                  <Link href="https://github.com/github" className={styles.Link}>
                    @github
                  </Link>
                  . Guardian of open-source seas, and whisker-twitching fan of yarn balls 🐙🧶
                </span>
                <SidebarSocialStats />
                <SidebarMatchingFollowers />
              </div>
              <SidebarSocialLinks />
            </div>
            <SidebarAchievements />
            <SidebarOrganizations />
          </PageLayout.Pane>
          <PageLayout.Content as="div" padding="none" className={styles.PageLayout_Content}>
            <div className={styles.Box_5}>
              <CustomReadme />
              <PinnedRepositories />
              <Contributions />
            </div>
          </PageLayout.Content>
        </main>
      </PageLayout>
    </div>
  )
}

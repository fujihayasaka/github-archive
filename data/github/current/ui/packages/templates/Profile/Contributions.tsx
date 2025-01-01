import {Heading, NavList, ActionMenu, ActionList, Timeline} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {FlameIcon, GitPullRequestIcon, EyeIcon} from '@primer/octicons-react'

import styles from './Contributions.module.css'

function Contributions() {
  return (
    <section aria-labelledby="contributions" className={styles.Box}>
      <div className={styles.Box_1}>
        <Heading id="contributions" as="h2" className={styles.Heading}>
          59 contributions in the last year
        </Heading>
        <div className={styles.Box_2}>
          <ActionMenu>
            <ActionMenu.Button>
              <span className={styles.Box_3}>Year:</span> {YEARS[0]}
            </ActionMenu.Button>
            <ActionMenu.Overlay width="auto" align="end">
              <ActionList>
                <ActionList.Group selectionVariant="single">
                  {YEARS.map((year, index) => (
                    <ActionList.Item key={year} selected={index === 0}>
                      {year}
                    </ActionList.Item>
                  ))}
                </ActionList.Group>
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        </div>
      </div>
      <div className={styles.Box_4}>
        <div className={styles.Box_5}>
          <div className={styles.Box_1}>
            <Heading as="h3" className={styles.Heading_1}>
              February <span className={styles.Box_3}>2024</span>
            </Heading>
            <div className={styles.Box_6} />
          </div>
          <Timeline>
            <Timeline.Item>
              <Timeline.Badge>
                <Octicon icon={EyeIcon} />
              </Timeline.Badge>
              <Timeline.Body>Reviewed 5 pull requests in 3 repositories</Timeline.Body>
            </Timeline.Item>
            <Timeline.Item>
              <Timeline.Badge>
                <Octicon icon={FlameIcon} />
              </Timeline.Badge>
              <Timeline.Body>
                Created a pull request in mona/playground that received 2 comments
                <div className={styles.Box_7}>
                  <div className={styles.Box_8}>
                    <Octicon icon={GitPullRequestIcon} className={styles.Octicon} />
                  </div>
                  <div className={styles.Box_9}>
                    <Heading as="h4" className={styles.Heading_2}>
                      Update playground.md
                    </Heading>
                    <span>Adding some octotastic additions to help hubbers achieve their dreams.</span>
                  </div>
                </div>
              </Timeline.Body>
            </Timeline.Item>
            <Timeline.Item>
              <Timeline.Badge>
                <Octicon icon={EyeIcon} />
              </Timeline.Badge>
              <Timeline.Body>Started 1 discussion in 1 repository</Timeline.Body>
            </Timeline.Item>
          </Timeline>
          <button className={styles.Box_10}>Show more activity</button>
        </div>
        <div className={styles.Box_11}>
          <NavList aria-label="Contributions by year">
            {YEARS.map((year, index) => (
              <NavList.Item key={year} href="#" aria-current={index === 0 && 'page'}>
                {year}
              </NavList.Item>
            ))}
          </NavList>
        </div>
      </div>
    </section>
  )
}

const YEARS = [2024, 2023, 2022, 2021, 2020, 2019, 2018]

export default Contributions

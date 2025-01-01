import {Heading, Label} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {VerifiedIcon, DownloadIcon} from '@primer/octicons-react'

import styles from './Featured.module.css'

const CARDS = [
  {
    image: 'https://github.com/primer/design/assets/980622/532571f5-cd42-4027-8793-98392cfc991d',
    name: 'Postman APIs',
    description: 'Build for developers who want to trigger an action in Postman from GitHub.',
    label: 'Copilot',
    downloads: 24200,
    verified: true,
  },
  {
    image: 'https://github.com/primer/design/assets/980622/7b5c1ed6-f3d3-4415-980b-761c166df2e1',
    name: 'Datadog monitoring',
    description: 'Modern monitoring & security. Review any stack, any app, at any scale.',
    label: 'Copilot',
    downloads: 16458,
    verified: false,
  },
  {
    image: 'https://github.com/primer/design/assets/980622/6dc2688f-6a82-4244-a772-3caa204c4f8f',
    name: 'Launch Darkly feature flags',
    description: 'Maximize the value of software feature via automation & feature management.',
    label: 'Copilot',
    downloads: 9725,
    verified: true,
  },
  {
    image: 'https://github.com/primer/design/assets/980622/17050734-0f6f-43c9-b285-c0c87148d982',
    name: 'Stripe',
    description: 'Financial infrastructure for the internet and modern companies.',
    label: 'Copilot',
    downloads: 22561,
    verified: true,
  },
  {
    image: 'https://github.com/primer/design/assets/980622/0b421923-ba03-4e8b-8562-83b54736a4bc',
    name: 'Sentry.io',
    description: 'Make sense of your unresolved issues happening within this files of your codebase.',
    label: 'Copilot',
    downloads: 48769,
    verified: true,
  },
  {
    image: 'https://github.com/primer/design/assets/980622/2a01f738-5928-43d1-84c2-d2336da10197',
    name: 'Docker',
    description: 'Accelerate how your company builds, shares, and runs applications in the cloud.',
    label: 'Copilot',
    downloads: 24992,
    verified: true,
  },
]

export default function Featured() {
  return (
    <div className={styles.Box}>
      <div className={styles.Box_1}>
        <Heading as="h2" className={styles.Heading}>
          Top starter Copilot plugins for your daily tasks
        </Heading>
        <span className={styles.Text}>Enhance and personalize Copilot based on your needs via third-party plugins</span>
      </div>
      <div className={styles.Box_2}>
        {CARDS.map(card => {
          return (
            <div key={card.name} className={styles.Box_3}>
              <img src={card.image} alt={card.name} className={styles.Box_4} />
              <div className={styles.Box_5}>
                <Heading as="h3" className={styles.Heading_1}>
                  {card.name} {card.verified && <Octicon icon={VerifiedIcon} className={styles.Octicon} />}
                </Heading>
                <span className={styles.Text_1}>{card.description}</span>
              </div>
              <div className={styles.Box_6}>
                <Label>{card.label}</Label>
                <div className={styles.Box_7}>
                  <Octicon icon={DownloadIcon} />
                  {card.downloads.toLocaleString()}
                </div>
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}

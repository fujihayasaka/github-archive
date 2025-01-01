import {Heading, Label, UnderlineNav} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {VerifiedIcon, DownloadIcon} from '@primer/octicons-react'

import styles from './Trending.module.css'

const CARDS = [
  {
    image: 'https://github.com/primer/design/assets/980622/146608e9-e72a-49bb-ba0e-150d67318c05',
    name: 'ZenHub',
    description: 'Project management tool that integrates natively within GitHub.',
    label: 'Apps',
    verified: false,
    downloads: 125,
  },
  {
    image: 'https://github.com/primer/design/assets/980622/95842309-b689-45c7-977a-9128e3c91904',
    name: 'Deploy to Vercel',
    description: 'Deploy your project to Vercel using GitHub Actions. Supports PR.',
    label: 'Actions',
    verified: false,
    downloads: 9245,
  },
  {
    image: 'https://github.com/primer/design/assets/980622/b8adf31b-9080-4576-a2ed-7978019ed40b',
    name: 'Pulumi',
    description: 'Gain better scale, more productivity, and faster time to market.',
    label: 'Copilot',
    verified: true,
    downloads: 2414,
  },
  {
    image: 'https://github.com/primer/design/assets/980622/8d5ba3d0-f963-4255-bd82-8beee388f2dc',
    name: 'Azure Pipelines',
    description: 'Continuously build, test, and deploy to any platform and cloud.',
    label: 'Actions',
    verified: true,
    downloads: 4350,
  },
  {
    image: 'https://github.com/primer/design/assets/980622/1c4cd32a-79eb-49eb-b4ef-53f0cfb9664c',
    name: 'Setup Go environment',
    description: 'Configure a Go environment and add it to the PATH.',
    label: 'Actions',
    verified: false,
    downloads: 524,
  },
  {
    image: 'https://github.com/primer/design/assets/980622/0f1e0852-9663-48cd-af65-d54cc339b2f9',
    name: 'Super-Linter',
    description: 'Ready-to-run collection of linters and code analyzers, to help…',
    label: 'Apps',
    verified: true,
    downloads: 202,
  },
]

const NAV_ITEMS = ['Trending this week', 'Recently added']

export default function Featured() {
  return (
    <div className={styles.Box}>
      <UnderlineNav aria-label="Repositories">
        {NAV_ITEMS.map((child, index) => (
          // eslint-disable-next-line @eslint-react/no-array-index-key
          <UnderlineNav.Item key={index} href="#" aria-current={index === 0 ? 'page' : undefined}>
            {child}
          </UnderlineNav.Item>
        ))}
      </UnderlineNav>
      <div className={styles.Box_1}>
        {CARDS.map(card => {
          return (
            <div key={card.name} className={styles.Box_2}>
              <img alt={card.name} src={card.image} className={styles.Box_3} />
              <div className={styles.Box_4}>
                <Heading as="h3" className={styles.Heading}>
                  {card.name} {card.verified && <Octicon icon={VerifiedIcon} className={styles.Octicon} />}
                </Heading>
                <span className={styles.Text}>{card.description}</span>
              </div>
              <div className={styles.Box_5}>
                <Label>{card.label}</Label>
                <div className={styles.Box_6}>
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

import {Box, Heading, Label, Link, IconButton} from '@primer/react'
import {Octicon, Tooltip} from '@primer/react/deprecated'
import {StarIcon, RepoForkedIcon, RepoIcon, PencilIcon} from '@primer/octicons-react'

import styles from './PinnedRepositories.module.css'

function PinnedRepositories() {
  const REPOSITORIES = [
    {
      id: 1,
      name: 'Playground',
      description: 'The quickest way to start playing around with Primer React.',
      language: 'JavaScript',
      languageColor: 'attention.fg',
      stars: 98,
      forks: 20,
      href: 'https://github.com/primer/react-template',
    },
    {
      id: 2,
      name: 'Notes',
      description: 'Tips and tricks to make your coding journey smoother and more fun!',
      language: 'TypeScript',
      languageColor: 'done.fg',
      stars: 12,
      forks: 5,
      href: 'https://github.com/primer/react-template',
    },
    {
      id: 3,
      name: 'Recipes',
      description: `The most delicious coding snacks, perfect for any developer's kitchen!`,
      language: 'Markdown',
      languageColor: 'success.fg',
      stars: 52,
      forks: 1,
      href: 'https://github.com/primer/react-template',
    },
    {
      id: 4,
      name: 'VSCode',
      description: 'The coolest extensions, themes, and shortcuts to supercharge your coding experience in VSCode!',
      language: 'C++',
      languageColor: 'sponsors.fg',
      stars: 52,
      forks: 8,
      href: 'https://github.com/primer/react-template',
    },
  ]
  return (
    <div className={styles.Box}>
      <div className={styles.Box_1}>
        <Heading as="h2" className={styles.Heading}>
          Pinned
        </Heading>
        <Tooltip aria-label="Edit pinned repositories">
          {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
          <IconButton
            unsafeDisableTooltip
            icon={PencilIcon}
            variant="invisible"
            aria-label="Edit pinned repositories"
          />
        </Tooltip>
      </div>
      <div className={styles.Box_2}>
        {REPOSITORIES.map(a => {
          return (
            <div key={a.id} className={styles.Box_3}>
              <div className={styles.Box_1}>
                <Octicon icon={RepoIcon} size={16} className={styles.Octicon} />
                <Link href={a.href} className={styles.Link}>
                  {a.name}
                </Link>
                <Label variant="secondary" className={styles.Label}>
                  Public
                </Label>
              </div>
              <div className={styles.Box_4}>{a.description}</div>
              <div className={styles.Box_5}>
                <div className={styles.Box_1}>
                  <Box
                    sx={{
                      bg: a.languageColor,
                    }}
                    className={styles.Box_6}
                  />
                  {a.language}
                </div>
                <div className={styles.Box_1}>
                  <Octicon icon={StarIcon} size={16} className={styles.Octicon_1} />
                  {a.stars}
                </div>
                <div className={styles.Box_1}>
                  <Octicon icon={RepoForkedIcon} size={16} className={styles.Octicon_1} />
                  {a.forks}
                </div>
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}

export default PinnedRepositories

import {Box, Heading} from '@primer/react'

import styles from './SidebarAchievements.module.css'

function SidebarAchievements() {
  return (
    <div className={styles.Box}>
      <Heading as="h2" className={styles.Heading}>
        Achievements
      </Heading>
      <div className={styles.Box_1}>
        {ACHIEVEMENTS.map(a => {
          return (
            <div key={a.id} className={styles.Box_2}>
              <img key={a.id} src={a.src} alt={a.alt} className={styles.Box_3} />
              <Box
                sx={{
                  bg: a.badgeColor,
                  display: a.total < 2 ? 'none' : 'flex',
                }}
                className={styles.Box_4}
              >
                x{a.total}
              </Box>
            </div>
          )
        })}
      </div>
    </div>
  )
}

const ACHIEVEMENTS = [
  {
    id: 0,
    src: 'https://github.githubassets.com/assets/pull-shark-default-498c279a747d.png',
    total: 4,
    badgeColor: 'accent.subtle',
    alt: 'Pull Shark',
  },
  {
    id: 1,
    src: 'https://github.githubassets.com/assets/yolo-default-be0bbff04951.png',
    total: 1,
    alt: 'YOLO',
  },
  {
    id: 2,
    src: 'https://github.githubassets.com/assets/starstruck-default-b6610abad518.png',
    total: 3,
    badgeColor: 'attention.subtle',
    alt: 'Starstruck',
  },
  {
    id: 3,
    src: 'https://github.githubassets.com/assets/quickdraw-default-39c6aec8ff89.png',
    total: 1,
    alt: 'Quickdraw',
  },
  {
    id: 4,
    src: 'https://github.githubassets.com/assets/pair-extraordinaire-default-579438a20e01.png',
    total: 2,
    badgeColor: 'success.subtle',
    alt: 'Pair Extraordinaire',
  },
  {
    id: 5,
    src: 'https://github.githubassets.com/assets/open-sourcerer-default-2acf5f6ff93e.png',
    total: 3,
    badgeColor: 'done.subtle',
    alt: 'Open Sourcerer',
  },
  {
    id: 6,
    src: 'https://github.githubassets.com/assets/heart-on-your-sleeve-default-f307e04d80f0.png',
    total: 1,
    alt: 'Heart On Your Sleeve',
  },
  {
    id: 7,
    src: 'https://github.githubassets.com/assets/arctic-code-vault-contributor-default-df8d74122a06.png',
    total: 1,
    alt: 'Arctic Code Vault Contributor',
  },
]

export default SidebarAchievements

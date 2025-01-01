import {useState} from 'react'
import type {PropsWithChildren} from 'react'
import {PageLayout} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import GlobalNavigation from './GlobalNavigation'
import Categories from './Categories'
import Featured from './Featured'
import Trending from './Trending'
import Header from './Header'

import {Dialog} from '@primer/react/experimental'
import {ChevronDownIcon} from '@primer/octicons-react'

import styles from './Marketplace.module.css'

export function Marketplace() {
  const pageTitle = 'Featured'
  return (
    <div className={styles.Box}>
      <GlobalNavigation />
      <Header />
      <PageLayout padding="none" rowGap="none" columnGap="none" className={styles.PageLayout}>
        <PageLayout.Pane
          position="start"
          padding="none"
          hidden={{
            narrow: true,
            regular: false,
            wide: false,
          }}
        >
          <Categories />
        </PageLayout.Pane>
        <PageLayout.Content padding="none" className={styles.PageLayout_Content}>
          <div className={styles.Box_1}>
            <div className={styles.Box_2}>
              <div className={styles.Box_3}>
                <div className={styles.Box_4}>
                  <MobileNavigationButton>
                    <div className={styles.Box_5}>Category:</div> {pageTitle}
                  </MobileNavigationButton>
                </div>
              </div>
            </div>
            <div className={styles.Box_6}>
              <Featured />
              <Trending />
            </div>
          </div>
        </PageLayout.Content>
      </PageLayout>
    </div>
  )
}

function MobileNavigationButton({children}: PropsWithChildren) {
  const [isOpen, setIsOpen] = useState(false)
  const onDialogClose = () => setIsOpen(false)
  return (
    <>
      <TitleButton onClick={() => setIsOpen(!isOpen)}>{children}</TitleButton>
      {isOpen && (
        <Dialog
          width="large"
          height="auto"
          renderBody={() => (
            <div className={styles.Box_7}>
              <Categories />
            </div>
          )}
          position={{narrow: 'bottom'}}
          title="Category"
          onClose={onDialogClose}
        />
      )}
    </>
  )
}

function TitleButton({children, onClick}: PropsWithChildren<{onClick: () => void}>) {
  return (
    <button onClick={onClick} className={styles.Box_8}>
      {children}
      <Octicon icon={ChevronDownIcon} size={16} className={styles.Octicon} />
    </button>
  )
}

import {useCallback, useEffect, useRef, useState} from 'react'
import {Link, Pagination} from '@primer/react'
import {Dialog} from '@primer/react/deprecated'
import {testIdProps} from '@github-ui/test-id-props'
import {verifiedFetch} from '@github-ui/verified-fetch'
import type {Dependency} from './types'

import styles from './DependenciesDialogBox.module.css'

interface DependenciesDialogBoxProps {
  isOpen: boolean
  setIsOpen: (isOpen: boolean) => void
  dependencyCount: number
  orgName: string
  sponsorableName: string
}

const DependenciesDialogBox = ({
  isOpen,
  setIsOpen,
  dependencyCount,
  orgName,
  sponsorableName,
}: DependenciesDialogBoxProps) => {
  // This PAGE_SIZE setting originates from this default setting: https://github.com/github/github/blob/169dea9cdeb71905654fbff385eb1fe6bb2272a9/app/controllers/sponsors/shared_dependencies_controller_methods.rb#L12
  // Since this is inherited from Rails, we're hardcoding it here, and it cannot be overridden via this React file.
  // To override this setting, do it in the `sponsors/represented_dependencies_controller` filter_set.
  const PAGE_SIZE = 8
  const [dependencies, setDependencies] = useState<Dependency[]>([])
  const [currentPaginatedPage, setCurrentPaginatedPage] = useState<number>(1)
  const returnFocusRef = useRef(null)
  const onPageChange: Parameters<typeof Pagination>['0']['onPageChange'] = (e, page) => {
    setCurrentPaginatedPage(page)
    e.preventDefault()
  }

  const getDependencies = useCallback(async () => {
    const url = `/sponsors/${sponsorableName}/represented-dependencies?account=${orgName}&page=${currentPaginatedPage}&format=json`
    const res = await verifiedFetch(url, {
      method: 'GET',
    })
    if (res?.ok) {
      const paginatedRepositories = await res.json()
      setDependencies(paginatedRepositories)
    }
  }, [currentPaginatedPage, orgName, sponsorableName])

  useEffect(() => {
    if (isOpen) {
      getDependencies()
    }
  }, [isOpen, getDependencies])

  return (
    <Dialog
      title="Repository List"
      onDismiss={() => {
        setIsOpen(false)
      }}
      isOpen={isOpen}
      {...testIdProps('dialog-box')}
      returnFocusRef={returnFocusRef}
      className={styles.Dialog}
    >
      <div>
        <Dialog.Header id="header">Repository List</Dialog.Header>
        <div className={styles.Box}>
          <div className={styles.Box_1}>
            <span className={styles.Text}>{orgName}</span>
            <span>&nbsp;depends on {dependencyCount} repositories</span>
            <span className={styles.Text}>&nbsp;{sponsorableName}</span>
            <span>&nbsp;owns or maintains</span>
          </div>
          <div>
            <div className={styles.Box_2}>
              <span className={styles.Text_1}>Repository Name</span>
            </div>
            <div>
              {/* TODO: Add loading state and empty/error state*/}
              {dependencies.map((dep: Dependency, index: number) => {
                return (
                  <div
                    // eslint-disable-next-line @eslint-react/no-array-index-key
                    key={index}
                    className={styles.Box_3}
                  >
                    <span>
                      <Link href={`https://github.com/${dep.fullRepoName}`}>{dep.name}</Link>
                    </span>
                  </div>
                )
              })}
              {dependencies.length > PAGE_SIZE && (
                <div className={styles.Box_4}>
                  <Pagination
                    pageCount={Math.ceil(dependencyCount / PAGE_SIZE)}
                    currentPage={currentPaginatedPage}
                    onPageChange={onPageChange}
                    showPages={{
                      narrow: false,
                    }}
                  />
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </Dialog>
  )
}

export default DependenciesDialogBox

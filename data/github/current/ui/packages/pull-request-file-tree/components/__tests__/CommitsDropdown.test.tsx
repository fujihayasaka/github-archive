import {screen} from '@testing-library/react'
import {noop} from '@github-ui/noop'
import {render} from '@github-ui/react-core/test-utils'
import {SelectedRefContext} from '../../contexts/SelectedRefContext'

import {getMockCommitsDropDownPageData} from '../../test-utils/mock-data'
import {CommitsDropdown} from '../CommitsDropdown'
import type {CommitsSelectorCommitData} from '../CommitsSelector'

const defaultMockData = getMockCommitsDropDownPageData()
const commit1Oid = defaultMockData.commits.at(0)!.oid
const commit2Oid = defaultMockData.commits.at(1)!.oid
const commit3Oid = defaultMockData.commits.at(2)!.oid

interface CommitsDropdownTestComponentProps {
  baseRefOid: string
  commits: CommitsSelectorCommitData[]
  endOid?: string | null
  lastReviewOid?: string
  isSingleCommit?: boolean
  startOid?: string | null
}

function CommitsDropdownTestComponent({
  baseRefOid,
  commits,
  endOid,
  lastReviewOid,
  isSingleCommit,
  startOid,
}: CommitsDropdownTestComponentProps) {
  return (
    <SelectedRefContext.Provider value={{endOid, isSingleCommit, startOid}}>
      <CommitsDropdown baseRefOid={baseRefOid} commits={commits} lastReviewOid={lastReviewOid} onRangeUpdated={noop} />
    </SelectedRefContext.Provider>
  )
}

describe('commit dropdown button text', () => {
  test('shows all changes when no commits selected', () => {
    render(<CommitsDropdownTestComponent {...defaultMockData} />)
    expect(screen.getByText('All changes')).toBeVisible()
  })

  test('shows single commit oid when single commit selected', () => {
    render(
      <CommitsDropdownTestComponent {...defaultMockData} endOid={commit2Oid} isSingleCommit startOid={commit1Oid} />,
    )
    expect(screen.getByText(`Commit ${commit2Oid.slice(0, 7)}`)).toBeVisible()
  })

  test('shows single commit oid when range has one commit', () => {
    render(<CommitsDropdownTestComponent {...defaultMockData} endOid={commit2Oid} startOid={commit1Oid} />)
    expect(screen.getByText(`Commit ${commit2Oid.slice(0, 7)}`)).toBeVisible()
  })

  test('shows correct commit range', () => {
    render(<CommitsDropdownTestComponent {...defaultMockData} endOid={commit3Oid} startOid={commit1Oid} />)
    expect(screen.getByText(`${commit2Oid.slice(0, 7)}..${commit3Oid.slice(0, 7)}`)).toBeVisible()
  })
})

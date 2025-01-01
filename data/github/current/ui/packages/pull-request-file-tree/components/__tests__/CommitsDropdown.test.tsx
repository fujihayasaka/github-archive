import {screen, within} from '@testing-library/react'
import {noop} from '@github-ui/noop'
import {render} from '@github-ui/react-core/test-utils'
import {SelectedRefContext} from '../../contexts/SelectedRefContext'

import {getMockCommitsDropDownPageData} from '../../test-utils/mock-data'
import {CommitsDropdown} from '../CommitsDropdown'
import type {CommitsSelectorCommitData} from '../CommitsSelector'

const defaultMockData = getMockCommitsDropDownPageData()
const commit1Oid = defaultMockData.commitOids.at(0)!
const commit2Oid = defaultMockData.commitOids.at(1)!
const commit3Oid = defaultMockData.commitOids.at(2)!

interface CommitsDropdownTestComponentProps {
  baseRefOid: string
  commitOids: string[]
  commits: CommitsSelectorCommitData[]
  endOid?: string | null
  isSingleCommit?: boolean
  startOid?: string | null
}

function CommitsDropdownTestComponent({
  baseRefOid,
  commitOids,
  commits,
  endOid,
  isSingleCommit,
  startOid,
}: CommitsDropdownTestComponentProps) {
  return (
    <SelectedRefContext.Provider value={{endOid, isSingleCommit, startOid}}>
      <CommitsDropdown baseRefOid={baseRefOid} commitOids={commitOids} commits={commits} onRangeUpdated={noop} />
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

describe('commit dropdown overlay', () => {
  test('shows expected options', async () => {
    const {user} = render(
      <CommitsDropdownTestComponent
        baseRefOid={defaultMockData.baseRefOid}
        commitOids={[commit1Oid]}
        commits={[defaultMockData.commits[0]!]}
      />,
    )

    await user.click(screen.getByRole('button'))

    const list = screen.getByRole('menu')
    expect(within(list).getByText('All changes')).toBeVisible()
    expect(screen.getByText('Specific commit…')).toBeVisible()
  })

  test('opens commit selector', async () => {
    const {user} = render(
      <CommitsDropdownTestComponent
        baseRefOid={defaultMockData.baseRefOid}
        commitOids={[commit1Oid]}
        commits={[defaultMockData.commits[0]!]}
      />,
    )

    await user.click(screen.getByRole('button'))
    await user.click(screen.getByText('Specific commit…'))

    expect(screen.getByText('Pick one or more commits')).toBeVisible()
  })
})

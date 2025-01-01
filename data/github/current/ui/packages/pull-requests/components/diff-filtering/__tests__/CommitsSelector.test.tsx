import {noop} from '@github-ui/noop'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {getMockCommitsDropDownPageData} from '../../../test-utils/files-changed/toolbar-mock-data'
import {CommitsSelector} from '../CommitsSelector'
import type {CommitSelection} from '../CommitsSelector'

const defaultMockData = getMockCommitsDropDownPageData()
const commitOids = defaultMockData.commits.map(commit => commit.oid)
const commit1Oid = commitOids.at(0)!
const commit2Oid = commitOids.at(1)!
const commit3Oid = commitOids.at(2)!
const baseRefOid = 'abc123'

interface CommitsSelectorTestComponentProps {
  endOid?: string | null
  onRangeUpdated?: (args: CommitSelection) => void
  onClose?: () => void
  startOid?: string | null
}

function CommitsSelectorTestComponent({
  onRangeUpdated = noop,
  onClose = noop,
  ...props
}: CommitsSelectorTestComponentProps) {
  const testProps = {...defaultMockData, ...props}
  return (
    <CommitsSelector
      {...testProps}
      commitOids={commitOids}
      onClose={onClose}
      onRangeUpdated={onRangeUpdated}
      baseRefOid={baseRefOid}
    />
  )
}

test('shows commit selector', () => {
  render(<CommitsSelectorTestComponent />)

  expect(screen.getByText('Pick one or more commits')).toBeVisible()
  expect(screen.getByText('Picking a range will select commits in between.')).toBeVisible()
  expect(screen.getByText(commit1Oid.slice(0, 7), {exact: false})).toBeVisible()
  expect(screen.getByText(commit2Oid.slice(0, 7), {exact: false})).toBeVisible()
  expect(screen.getByText(commit3Oid.slice(0, 7), {exact: false})).toBeVisible()
  expect(screen.getAllByText('monalisa', {exact: false}).length).toBe(3)
})

describe('commit selector logic', () => {
  test('inclusively selects and de-selects items', async () => {
    const {user} = render(<CommitsSelectorTestComponent />)

    expect(screen.getByText('Pick one or more commits')).toBeVisible()

    // select the first item and verify that it is selected
    await user.click(screen.getByText('commit 1'))
    expect(screen.getByRole('option', {name: /commit 1/})).toHaveAttribute('aria-selected', 'true')

    // select the third item and verify that all options selected
    await user.click(screen.getByText('commit 3'))
    expect(screen.getByRole('option', {name: /commit 1/})).toHaveAttribute('aria-selected', 'true')
    expect(screen.getByRole('option', {name: /commit 2/})).toHaveAttribute('aria-selected', 'true')
    expect(screen.getByRole('option', {name: /commit 3/})).toHaveAttribute('aria-selected', 'true')

    // click the second item and verify that items 2 and 3 are not selected
    await user.click(screen.getByText('commit 2'))
    expect(screen.getByRole('option', {name: /commit 1/})).toHaveAttribute('aria-selected', 'true')
    expect(screen.getByRole('option', {name: /commit 2/})).not.toHaveAttribute('aria-selected', 'true')
    expect(screen.getByRole('option', {name: /commit 3/})).not.toHaveAttribute('aria-selected', 'true')

    // click the first item and verify that nothing is selected
    await user.click(screen.getByText('commit 1'))
    expect(screen.getByRole('option', {name: /commit 1/})).not.toHaveAttribute('aria-selected', 'true')
    expect(screen.getByRole('option', {name: /commit 2/})).not.toHaveAttribute('aria-selected', 'true')
    expect(screen.getByRole('option', {name: /commit 3/})).not.toHaveAttribute('aria-selected', 'true')
  })

  describe('initial selection state', () => {
    describe('with range', () => {
      test('including start commit', () => {
        render(<CommitsSelectorTestComponent endOid={commit2Oid} startOid={baseRefOid} />)

        expect(screen.getByText('Pick one or more commits')).toBeVisible()

        // select the first item and verify that it is selected
        expect(screen.getByRole('option', {name: /commit 1/})).toHaveAttribute('aria-selected', 'true')
        expect(screen.getByRole('option', {name: /commit 2/})).toHaveAttribute('aria-selected', 'true')
        expect(screen.getByRole('option', {name: /commit 3/})).toHaveAttribute('aria-selected', 'false')
      })

      test('including end commit', () => {
        render(<CommitsSelectorTestComponent endOid={commit3Oid} startOid={commit1Oid} />)

        expect(screen.getByText('Pick one or more commits')).toBeVisible()

        // select the first item and verify that it is selected
        expect(screen.getByRole('option', {name: /commit 1/})).toHaveAttribute('aria-selected', 'false')
        expect(screen.getByRole('option', {name: /commit 2/})).toHaveAttribute('aria-selected', 'true')
        expect(screen.getByRole('option', {name: /commit 3/})).toHaveAttribute('aria-selected', 'true')
      })

      test('excluding start and end commit', () => {
        render(<CommitsSelectorTestComponent endOid={commit3Oid} startOid={commit1Oid} />)

        expect(screen.getByText('Pick one or more commits')).toBeVisible()

        // select the first item and verify that it is selected
        expect(screen.getByRole('option', {name: /commit 1/})).toHaveAttribute('aria-selected', 'false')
        expect(screen.getByRole('option', {name: /commit 2/})).toHaveAttribute('aria-selected', 'true')
        expect(screen.getByRole('option', {name: /commit 3/})).toHaveAttribute('aria-selected', 'true')
      })
    })

    test('with single commit', () => {
      render(<CommitsSelectorTestComponent endOid={commit3Oid} startOid={commit2Oid} />)

      expect(screen.getByText('Pick one or more commits')).toBeVisible()
      expect(screen.getByRole('option', {name: /commit 1/})).toHaveAttribute('aria-selected', 'false')
      expect(screen.getByRole('option', {name: /commit 2/})).toHaveAttribute('aria-selected', 'false')
      expect(screen.getByRole('option', {name: /commit 3/})).toHaveAttribute('aria-selected', 'true')
    })
  })

  describe('commit selector apply changes', () => {
    test('with single commit selected', async () => {
      const changeCommittedMock = jest.fn<void, [CommitSelection]>()

      const {user} = render(<CommitsSelectorTestComponent onRangeUpdated={changeCommittedMock} />)

      expect(screen.getByText('Pick one or more commits')).toBeVisible()

      await user.click(screen.getByRole('option', {name: /commit 1/}))
      await user.click(screen.getByText('Save'))

      const expected: CommitSelection = {type: 'single', oid: commit1Oid}
      expect(changeCommittedMock).toHaveBeenCalledWith(expected)
    })

    test('with range selected', async () => {
      const changeCommittedMock = jest.fn<void, [CommitSelection]>()

      const {user} = render(<CommitsSelectorTestComponent onRangeUpdated={changeCommittedMock} />)

      expect(screen.getByText('Pick one or more commits')).toBeVisible()

      await user.click(screen.getByRole('option', {name: /commit 2/}))
      await user.click(screen.getByRole('option', {name: /commit 3/}))
      await user.click(screen.getByText('Save'))

      const expected: CommitSelection = {type: 'range', fromPRBase: false, baseOid: commit1Oid, endOid: commit3Oid}
      expect(changeCommittedMock).toHaveBeenCalledWith(expected)
    })

    test('with range selected including the first commit', async () => {
      const changeCommittedMock = jest.fn<void, [CommitSelection]>()

      const {user} = render(<CommitsSelectorTestComponent onRangeUpdated={changeCommittedMock} />)

      expect(screen.getByText('Pick one or more commits')).toBeVisible()

      await user.click(screen.getByRole('option', {name: /commit 1/}))
      await user.click(screen.getByRole('option', {name: /commit 2/}))
      await user.click(screen.getByText('Save'))

      const expected: CommitSelection = {type: 'range', fromPRBase: true, baseOid: baseRefOid, endOid: commit2Oid}
      expect(changeCommittedMock).toHaveBeenCalledWith(expected)
    })

    test('with all commits selected and initial single commit', async () => {
      const changeCommittedMock = jest.fn<void, [CommitSelection]>()

      const {user} = render(
        <CommitsSelectorTestComponent endOid={commit1Oid} startOid={baseRefOid} onRangeUpdated={changeCommittedMock} />,
      )

      expect(screen.getByText('Pick one or more commits')).toBeVisible()

      await user.click(screen.getByRole('option', {name: /commit 2/}))
      await user.click(screen.getByRole('option', {name: /commit 3/}))
      await user.click(screen.getByText('Save'))

      const expected: CommitSelection = {type: 'unfiltered'}
      expect(changeCommittedMock).toHaveBeenCalledWith(expected)
    })

    test('with all commits selected and empty initial range', async () => {
      const changeCommittedMock = jest.fn<void, [CommitSelection]>()
      const onCloseMock = jest.fn<void, []>()

      const {user} = render(<CommitsSelectorTestComponent onRangeUpdated={changeCommittedMock} onClose={onCloseMock} />)

      expect(screen.getByText('Pick one or more commits')).toBeVisible()

      await user.click(screen.getByRole('option', {name: /commit 1/}))
      await user.click(screen.getByRole('option', {name: /commit 2/}))
      await user.click(screen.getByRole('option', {name: /commit 3/}))
      await user.click(screen.getByText('Save'))

      expect(changeCommittedMock).not.toHaveBeenCalled()
      expect(onCloseMock).toHaveBeenCalled()
    })
  })

  test('clearing selection', async () => {
    const {user} = render(<CommitsSelectorTestComponent endOid={commit3Oid} startOid={commit2Oid} />)

    expect(screen.getByText('Pick one or more commits')).toBeVisible()

    expect(screen.getByRole('option', {name: /commit 1/})).toHaveAttribute('aria-selected', 'false')
    expect(screen.getByRole('option', {name: /commit 2/})).toHaveAttribute('aria-selected', 'false')
    expect(screen.getByRole('option', {name: /commit 3/})).toHaveAttribute('aria-selected', 'true')

    await user.click(screen.getByRole('button', {name: 'Clear selection'}))

    expect(screen.getByRole('option', {name: /commit 1/})).toHaveAttribute('aria-selected', 'false')
    expect(screen.getByRole('option', {name: /commit 2/})).toHaveAttribute('aria-selected', 'false')
    expect(screen.getByRole('option', {name: /commit 3/})).toHaveAttribute('aria-selected', 'false')
  })
})

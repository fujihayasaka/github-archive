import {render, screen} from '@testing-library/react'
import {LinkedBranches} from '../development-section/LinkedBranches'
import type {BranchPickerRef$data} from '@github-ui/item-picker/BranchPickerRef.graphql'

test('escapes branch names in URL', async () => {
  const linkedBranches = [
    {
      id: '1',
      name: 'feature/branch#test',
      repository: {
        id: '1',
        nameWithOwner: 'owner/repo',
      },
    },
  ]

  render(<LinkedBranches linkedBranches={linkedBranches as BranchPickerRef$data[]} />)

  const linkElement = screen.getByRole('link')
  expect(linkElement).toHaveAttribute('href', '/owner/repo/tree/feature%2Fbranch%23test')
  expect(linkElement).toHaveTextContent('feature/branch#test')
})

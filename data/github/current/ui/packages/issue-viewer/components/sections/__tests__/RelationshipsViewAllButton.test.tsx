import {render, screen, act} from '@testing-library/react'
import {RelationshipsViewAllButton} from '../relations-section/RelationshipsViewAllButton'
import {LABELS} from '../../../constants/labels'

test('renders dialog containing the passed title when the button is clicked', async () => {
  const expectedTitle = 'test title'
  render(<RelationshipsViewAllButton dialogTitle={expectedTitle} countOpenItems={0} />)

  const viewAll = screen.getByRole('listitem', {name: LABELS.relationViewAll})

  act(() => viewAll.click())

  expect(await screen.findByText(expectedTitle)).toBeInTheDocument()
})

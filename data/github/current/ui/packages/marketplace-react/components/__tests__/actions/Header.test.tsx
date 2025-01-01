import {Header} from '../../actions/Header'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockActionListing} from '@github-ui/marketplace-common/mock-data'
import {mockRepository, mockDelistActionData} from '../../../test-utils/mock-data'

describe('Header', () => {
  const actionListing = mockActionListing()
  const repository = mockRepository()
  const delistActionData = mockDelistActionData()

  test('Renders the overview header', () => {
    render(<Header action={actionListing} repository={repository} delistActionData={delistActionData} />)

    expect(screen.getByTestId('overview-header')).toBeInTheDocument()
  })

  test('Renders breadcrumbs', () => {
    render(<Header action={actionListing} repository={repository} delistActionData={delistActionData} />)

    expect(screen.getByRole('navigation', {name: 'Breadcrumbs'})).toBeInTheDocument()
  })

  test('Renders the delist button', () => {
    render(<Header action={actionListing} repository={repository} delistActionData={delistActionData} />)

    expect(screen.getByTestId('delist-button')).toBeInTheDocument()
  })

  test('Renders the about section', () => {
    render(<Header action={actionListing} repository={repository} delistActionData={delistActionData} />)

    expect(screen.getByTestId('about')).toBeInTheDocument()
  })

  test('Renders the tags section', () => {
    render(<Header action={actionListing} repository={repository} delistActionData={delistActionData} />)

    expect(screen.getByTestId('tags')).toBeInTheDocument()
  })
})

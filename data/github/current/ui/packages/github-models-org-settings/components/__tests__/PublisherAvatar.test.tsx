import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {mockPublisher} from '../../test-utils/mocks'
import {PublisherAvatar} from '../PublisherAvatar'

describe('PublisherAvatar', () => {
  it('renders', () => {
    const publisher = mockPublisher({logoUrl: '/some/image/path.png', name: 'Fancy Publisher'})

    render(<PublisherAvatar publisher={publisher} />)

    const img = screen.getByRole('img', {name: 'Fancy Publisher logo'})
    expect(img).toBeInTheDocument()
    expect(img).toHaveAttribute('src', '/some/image/path.png')
  })
})

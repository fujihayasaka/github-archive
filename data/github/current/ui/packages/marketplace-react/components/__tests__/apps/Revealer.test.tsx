import {render} from '@github-ui/react-core/test-utils'
import {screen, act, waitFor} from '@testing-library/react'
import {Revealer} from '../../apps/Revealer'

describe('Revealer', () => {
  it('renders the title', () => {
    render(
      <Revealer title="Title" defaultOpen={false}>
        Content
      </Revealer>,
    )

    expect(screen.getByRole('heading', {name: 'Title'})).toBeInTheDocument()
  })

  it('renders the children content when the section is expanded when open is false', async () => {
    render(
      <Revealer title="Title" defaultOpen={false}>
        Content
      </Revealer>,
    )

    expect(screen.queryByText('Content')).not.toBeInTheDocument()

    const heading = screen.getByRole('heading', {name: 'Title'})
    act(() => heading.click())

    await waitFor(() => {
      expect(screen.getByText('Content')).toBeInTheDocument()
    })
  })

  it('renders the children content by default when open is true', () => {
    render(
      <Revealer title="Title" defaultOpen>
        Content
      </Revealer>,
    )

    expect(screen.getByText('Content')).toBeInTheDocument()
  })

  it('hides the children content when the section is collapsed', async () => {
    render(
      <Revealer title="Title" defaultOpen>
        Content
      </Revealer>,
    )

    expect(screen.getByText('Content')).toBeInTheDocument()

    const heading = screen.getByRole('heading', {name: 'Title'})
    act(() => heading.click())

    await waitFor(() => {
      expect(screen.queryByText('Content')).not.toBeInTheDocument()
    })
  })
})

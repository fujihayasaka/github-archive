import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {Button, DismissibleBanner} from '../../components/Components'

describe('Button', () => {
  it('calls onClick when inactive is not set', async () => {
    const onClick = jest.fn()
    const {user} = render(<Button onClick={onClick}>Foo</Button>)
    await user.click(screen.getByRole('button'))
    expect(onClick).toHaveBeenCalled()
  })

  it('does not call onClick when inactive is true', async () => {
    const onClick = jest.fn()
    const {user} = render(
      <Button onClick={onClick} inactive>
        Foo
      </Button>,
    )
    await user.click(screen.getByRole('button'))
    expect(onClick).not.toHaveBeenCalled()
  })
})

describe('DismissibleBanner', () => {
  it('hides the banner on dismiss', async () => {
    const {user} = render(<DismissibleBanner title="Foo" />)
    expect(screen.getByText('Foo')).toBeInTheDocument()
    await user.click(screen.getByLabelText('Dismiss banner'))
    expect(screen.queryByText('Foo')).not.toBeInTheDocument()
  })

  it('calls onDismiss when the banner is dismissed', async () => {
    const onDismiss = jest.fn()
    const {user} = render(<DismissibleBanner title="Foo" onDismiss={onDismiss} />)
    expect(screen.getByText('Foo')).toBeInTheDocument()
    await user.click(screen.getByLabelText('Dismiss banner'))
    expect(onDismiss).toHaveBeenCalled()
    expect(screen.queryByText('Foo')).not.toBeInTheDocument()
  })
})

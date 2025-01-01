import {screen} from '@testing-library/react'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {RocketIcon} from '@primer/octicons-react'
import {Card} from '../src/Card'

describe('Card', () => {
  test('renders a link card with all subcomponents', () => {
    render(
      <Card href="/destination">
        <Card.Icon icon={RocketIcon} color="coral" />
        <Card.Heading>Link Card Example</Card.Heading>
        <Card.Description>Click this card to navigate to a different page.</Card.Description>
        <Card.Metadata>Last updated: 2025-04-10 12:34:55</Card.Metadata>
      </Card>,
    )

    const link = screen.getByRole('link')
    expect(link).toHaveAttribute('href', '/destination')
    expect(link).toHaveTextContent('Link Card Example')
    expect(link).toHaveTextContent('Click this card to navigate to a different page.')
    expect(link).toHaveTextContent('Last updated: 2025-04-10 12:34:55')
  })

  test('renders a button card with all subcomponents', async () => {
    const handleClick = jest.fn()
    const user = setupUserEvent()

    render(
      <Card onClick={handleClick}>
        <Card.Icon icon={RocketIcon} />
        <Card.Heading>Button Card Example</Card.Heading>
        <Card.Description>Click this card to trigger an action.</Card.Description>
        <Card.Metadata>User: dipree</Card.Metadata>
      </Card>,
    )

    const button = screen.getByRole('button')
    expect(button).toHaveTextContent('Button Card Example')
    expect(button).toHaveTextContent('Click this card to trigger an action.')
    expect(button).toHaveTextContent('User: dipree')

    await user.click(button)
    expect(handleClick).toHaveBeenCalledTimes(1)
  })

  test('renders card with minimal content', () => {
    render(
      <Card href="/minimal">
        <Card.Heading>Just a Heading</Card.Heading>
      </Card>,
    )

    const link = screen.getByRole('link')
    expect(link).toHaveTextContent('Just a Heading')
    expect(link).not.toHaveTextContent('Description')
  })
})

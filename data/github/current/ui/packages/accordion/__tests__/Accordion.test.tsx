import React from 'react'
import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {Accordion} from '../Accordion'

describe('Accordion component', () => {
  it('renders an accordion without crashing', () => {
    render(
      <Accordion data-testid="accordion" expandedItems={[]} onChange={() => {}}>
        <Accordion.Item value="test">
          <Accordion.Trigger>Test Section</Accordion.Trigger>
          <Accordion.Content>Test content</Accordion.Content>
        </Accordion.Item>
      </Accordion>,
    )
    expect(screen.getByTestId('accordion')).toBeInTheDocument()
  })

  describe('Accordion.Item', () => {
    it('renders content hidden by default', () => {
      render(
        <Accordion expandedItems={[]} onChange={() => {}}>
          <Accordion.Item value="test">
            <Accordion.Trigger>Test Section</Accordion.Trigger>
            <Accordion.Content>Test content</Accordion.Content>
          </Accordion.Item>
        </Accordion>,
      )

      expect(screen.getByText('Test content')).not.toBeVisible()
    })

    it('shows content when item is expanded', () => {
      render(
        <Accordion expandedItems={['test']} onChange={() => {}}>
          <Accordion.Item value="test">
            <Accordion.Trigger>Test Section</Accordion.Trigger>
            <Accordion.Content>Test content</Accordion.Content>
          </Accordion.Item>
        </Accordion>,
      )

      expect(screen.getByText('Test content')).toBeVisible()
    })
  })

  describe('controlled behavior', () => {
    const ControlledAccordion = ({handleChange}: {handleChange: (items: string[]) => void}) => {
      const [expanded, setExpanded] = React.useState<string[]>([])

      const onChange = (newItems: string[]) => {
        setExpanded(newItems)
        handleChange(newItems)
      }

      return (
        <Accordion expandedItems={expanded} onChange={onChange}>
          <Accordion.Item value="test">
            <Accordion.Trigger>Test Section</Accordion.Trigger>
            <Accordion.Content>Test content</Accordion.Content>
          </Accordion.Item>
        </Accordion>
      )
    }

    it('handles expansion state changes correctly', async () => {
      const handleChange = jest.fn()
      const {user} = render(<ControlledAccordion handleChange={handleChange} />)

      await user.click(screen.getByText('Test Section'))
      expect(handleChange).toHaveBeenCalledWith(['test'])
    })

    it('supports keyboard interaction', async () => {
      const handleChange = jest.fn()
      const {user} = render(<ControlledAccordion handleChange={handleChange} />)

      // Get the button element instead of the text
      const trigger = screen.getByRole('button', {name: 'Test Section'})
      await user.tab()
      expect(trigger).toHaveFocus()

      await user.keyboard('{Enter}')
      expect(handleChange).toHaveBeenCalledWith(['test'])

      await user.keyboard(' ')
      expect(handleChange).toHaveBeenCalledWith([])
    })
  })

  describe('accessibility', () => {
    it('has correct ARIA attributes', () => {
      render(
        <Accordion expandedItems={[]} onChange={() => {}}>
          <Accordion.Item value="test">
            <Accordion.Trigger>Test Section</Accordion.Trigger>
            <Accordion.Content>Test content</Accordion.Content>
          </Accordion.Item>
        </Accordion>,
      )

      // Get the button element instead of the text
      const trigger = screen.getByRole('button', {name: 'Test Section'})
      expect(trigger).toHaveAttribute('aria-expanded', 'false')
      expect(trigger).toHaveAttribute('type', 'button')
      expect(trigger).toHaveAttribute('aria-controls', 'content-test')
    })
  })
})

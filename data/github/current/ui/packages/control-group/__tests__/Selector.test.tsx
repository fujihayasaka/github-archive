import type React from 'react'
import {ControlGroup} from '../ControlGroup'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

type SelectorProps = React.ComponentProps<typeof ControlGroup.Selector>

const modes: SelectorProps['modes'] = [
  {
    name: 'all',
    label: 'All-label',
    description: 'All-description',
  },
  {
    name: 'custom',
    label: 'Custom-label',
    description: 'Custom-description',
    editorLabel: 'Custom-editor-label',
    editorDescription: 'Custom-editor-description',
    renderEditor: ({shouldOpen}) => <div>Custom-editor-content {shouldOpen && <span>Opened</span>}</div>,
  },
]

describe('ControlGroup.ModeBaseSelector', () => {
  test('renders a single row if only one mode', () => {
    render(
      <ControlGroup>
        <ControlGroup.Selector
          title="Selection-title"
          description="Selection-description"
          selectedMode={undefined}
          modes={[modes[1]!]}
        />
      </ControlGroup>,
    )

    expect(screen.getByText('Selection-title')).toBeInTheDocument()
    expect(screen.getByText('Selection-description')).toBeInTheDocument()
    expect(screen.queryByText('Custom-label')).not.toBeInTheDocument()
    expect(screen.queryByText('Custom-description')).not.toBeInTheDocument()
    expect(screen.queryByText('Custom-editor-label')).not.toBeInTheDocument()
    expect(screen.queryByText('Custom-editor-description')).not.toBeInTheDocument()
    expect(screen.getByText('Custom-editor-content')).toBeInTheDocument()
  })

  test('renders a selector row if more than 1 mode', async () => {
    const {user} = render(
      <ControlGroup>
        <ControlGroup.Selector
          title="Selection-title"
          description="Selection-description"
          selectedMode={modes[0]!.name}
          modes={modes}
        />
      </ControlGroup>,
    )

    expect(screen.getByText('Selection-title')).toBeInTheDocument()
    expect(screen.getByText('Selection-description')).toBeInTheDocument()

    const selector = screen.getByText('All-label')
    expect(selector).toBeInTheDocument()
    await user.click(selector)

    expect(screen.getAllByText('All-label')).toHaveLength(2)
    expect(screen.getByText('All-description')).toBeInTheDocument()
    expect(screen.getByText('Custom-label')).toBeInTheDocument()
    expect(screen.getByText('Custom-description')).toBeInTheDocument()
  })

  test('renders the editor when the selected mode defines it', async () => {
    render(
      <ControlGroup>
        <ControlGroup.Selector
          title="Selection-title"
          description="Selection-description"
          selectedMode="custom"
          modes={modes}
        />
      </ControlGroup>,
    )

    expect(screen.getByText('Selection-title')).toBeInTheDocument()
    expect(screen.getByText('Selection-description')).toBeInTheDocument()
    expect(screen.getByText('Custom-label')).toBeInTheDocument()

    expect(screen.getByText('Custom-editor-label')).toBeInTheDocument()
    expect(screen.getByText('Custom-editor-description')).toBeInTheDocument()
    expect(screen.getByText('Custom-editor-content')).toBeInTheDocument()
    expect(screen.queryByText('Opened')).not.toBeInTheDocument()
  })

  test('opens the new editor when user changes mode', async () => {
    const {user, rerender} = render(
      <ControlGroup>
        <ControlGroup.Selector title="" description="" selectedMode="all" modes={modes} />
      </ControlGroup>,
    )

    const selector = screen.getByText('All-label')
    await user.click(selector)

    await user.click(screen.getByText('Custom-label'))
    rerender(
      <ControlGroup>
        <ControlGroup.Selector title="" description="" selectedMode="custom" modes={modes} />
      </ControlGroup>,
    )

    expect(screen.getByText('Custom-editor-label')).toBeInTheDocument()
    expect(screen.getByText('Custom-editor-description')).toBeInTheDocument()
    expect(screen.getByText('Custom-editor-content')).toBeInTheDocument()
    expect(screen.getByText('Opened')).toBeInTheDocument()
  })

  test('does not open new editor dialog when selected mode is changed programmatically', async () => {
    const {rerender} = render(
      <ControlGroup>
        <ControlGroup.Selector title="" description="" selectedMode="all" modes={modes} />
      </ControlGroup>,
    )

    expect(screen.getByText('All-label')).toBeInTheDocument()

    rerender(
      <ControlGroup>
        <ControlGroup.Selector title="" description="" selectedMode="custom" modes={modes} />
      </ControlGroup>,
    )

    expect(screen.getByText('Custom-label')).toBeInTheDocument()
    expect(screen.queryByText('Opened')).not.toBeInTheDocument()
  })

  test('shouldOpen ref is correctly set after editor dialog is opened and then closed', async () => {
    const {user, rerender} = render(
      <ControlGroup>
        <ControlGroup.Selector title="" description="" selectedMode="all" modes={modes} />
      </ControlGroup>,
    )
    await user.click(screen.getByText('All-label'))
    await user.click(screen.getByText('Custom-label'))

    rerender(
      <ControlGroup>
        <ControlGroup.Selector title="" description="" selectedMode="custom" modes={modes} />
      </ControlGroup>,
    )

    expect(screen.getByText('Custom-editor-content')).toBeInTheDocument()
    expect(screen.getByText('Opened')).toBeInTheDocument()

    rerender(
      <ControlGroup>
        <ControlGroup.Selector title="" description="" selectedMode="all" modes={modes} />
      </ControlGroup>,
    )
    expect(screen.queryByText('Opened')).not.toBeInTheDocument()

    await user.click(screen.getByText('All-label'))
    await user.click(screen.getByText('Custom-label'))

    rerender(
      <ControlGroup>
        <ControlGroup.Selector title="" description="" selectedMode="custom" modes={modes} />
      </ControlGroup>,
    )

    expect(screen.getByText('Custom-editor-content')).toBeInTheDocument()
    expect(screen.getByText('Opened')).toBeInTheDocument()
  })
})

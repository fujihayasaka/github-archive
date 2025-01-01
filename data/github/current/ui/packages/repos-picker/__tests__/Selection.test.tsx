import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {Selection} from '../Selection'

type SelectionProps = React.ComponentProps<typeof Selection>

const modes: SelectionProps['modes'] = [
  {
    name: 'all',
    label: 'All-label',
    description: 'All-description',
  },
  {
    name: 'multiple',
    label: 'Multiple-label',
    description: 'Multiple-description',
    editorLabel: 'Multiple-editor-label',
    editorDescription: 'Multiple-editor-description',
    renderEditor: () => <div>Multiple-editor-content</div>,
  },
]

describe('Selection', () => {
  test('renders a single row if only one mode', () => {
    renderSelection({modes: [modes[1]!], selectedMode: undefined})

    expect(screen.getByText('Selection-title')).toBeInTheDocument()
    expect(screen.getByText('Selection-description')).toBeInTheDocument()
    expect(screen.queryByText('Multiple-label')).not.toBeInTheDocument()
    expect(screen.queryByText('Multiple-description')).not.toBeInTheDocument()
    expect(screen.queryByText('Multiple-editor-label')).not.toBeInTheDocument()
    expect(screen.queryByText('Multiple-editor-description')).not.toBeInTheDocument()
    expect(screen.getByText('Multiple-editor-content')).toBeInTheDocument()
  })

  test('renders a selector row if more than 1 mode', async () => {
    const {user} = renderSelection({modes})

    expect(screen.getByText('Selection-title')).toBeInTheDocument()
    expect(screen.getByText('Selection-description')).toBeInTheDocument()

    const selector = screen.getByText('All-label')
    expect(selector).toBeInTheDocument()
    await user.click(selector)

    expect(screen.getAllByText('All-label')).toHaveLength(2)
    expect(screen.getByText('All-description')).toBeInTheDocument()
    expect(screen.getByText('Multiple-label')).toBeInTheDocument()
    expect(screen.getByText('Multiple-description')).toBeInTheDocument()
  })

  test('renders the editor when the selected mode defines it', async () => {
    renderSelection({modes, selectedMode: 'multiple'})

    expect(screen.getByText('Selection-title')).toBeInTheDocument()
    expect(screen.getByText('Selection-description')).toBeInTheDocument()
    expect(screen.getByText('Multiple-label')).toBeInTheDocument()

    expect(screen.getByText('Multiple-editor-label')).toBeInTheDocument()
    expect(screen.getByText('Multiple-editor-description')).toBeInTheDocument()
    expect(screen.getByText('Multiple-editor-content')).toBeInTheDocument()
  })
})

function renderSelection(props: Partial<SelectionProps> = {}) {
  return render(
    <Selection
      title="Selection-title"
      description="Selection-description"
      selectedMode={modes[0]!.name}
      modes={modes}
      {...props}
    />,
  )
}

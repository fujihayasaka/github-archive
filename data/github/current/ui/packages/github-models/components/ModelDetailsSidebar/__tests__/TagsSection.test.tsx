import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {TagsSection} from '../TagsSection'
import type {Labels} from '../../../routes/playground/components/types'

describe('TagsSection', () => {
  test('renders with task and tags', () => {
    const labels: Labels = {task: 'walk', tags: ['aerobic', 'exercise']}

    const {container} = render(<TagsSection labels={labels} />)

    expect(within(container).getByTestId('tags-section')).toBeInTheDocument()
    expect(within(container).getByRole('heading', {name: 'Tags', level: 3})).toBeInTheDocument()
    const links = within(container).getAllByRole('link')
    expect(links).toHaveLength(3)
    expect(links[0]).toHaveTextContent('aerobic')
    expect(links[0]).toHaveAttribute('href', `/marketplace?type=models&category=aerobic`)
    expect(links[1]).toHaveTextContent('exercise')
    expect(links[1]).toHaveAttribute('href', `/marketplace?type=models&category=exercise`)
    expect(links[2]).toHaveTextContent('walk')
    expect(links[2]).toHaveAttribute('href', `/marketplace?type=models&task=walk`)
  })

  test('renders with just a task and no tags', () => {
    const labels: Labels = {task: 'consider', tags: []}

    const {container} = render(<TagsSection labels={labels} />)

    expect(within(container).getByTestId('tags-section')).toBeInTheDocument()
    expect(within(container).getByRole('heading', {name: 'Tags', level: 3})).toBeInTheDocument()
    const link = within(container).getByRole('link')
    expect(link).toHaveTextContent('consider')
    expect(link).toHaveAttribute('href', `/marketplace?type=models&task=consider`)
  })

  test('renders with just a tag and no task', () => {
    const labels: Labels = {task: '', tags: ['Foo']}

    const {container} = render(<TagsSection labels={labels} />)

    expect(within(container).getByTestId('tags-section')).toBeInTheDocument()
    expect(within(container).getByRole('heading', {name: 'Tags', level: 3})).toBeInTheDocument()
    const link = within(container).getByRole('link')
    expect(link).toHaveTextContent('Foo')
    expect(link).toHaveAttribute('href', `/marketplace?type=models&category=Foo`)
  })

  test('renders with specified heading level', () => {
    const labels: Labels = {task: 'walk', tags: ['aerobic', 'exercise']}

    const {container} = render(<TagsSection labels={labels} headingLevel="h2" />)

    expect(within(container).getByRole('heading', {name: 'Tags', level: 2})).toBeInTheDocument()
  })

  test('normalizes tags in URLs', () => {
    const labels: Labels = {task: 'chat', tags: ['First-Word-Second-Word']}

    const {container} = render(<TagsSection labels={labels} />)

    const links = within(container).getAllByRole('link')
    expect(links).toHaveLength(2)
    expect(links[0]).toHaveTextContent('First-Word-Second-Word')
    expect(links[0]).toHaveAttribute('href', `/marketplace?type=models&category=First-Word-Second-Word`)
    expect(links[1]).toHaveTextContent('chat')
    expect(links[1]).toHaveAttribute('href', `/marketplace?type=models&task=chat`)
  })
})

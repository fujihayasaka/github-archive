import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {SubmoduleDiff} from '../SubmoduleDiff'
import {mockSubmodule, mockSubmoduleWithoutSummaries} from '../../test-utils/mock-data'
import type {SubmoduleDiff as SubmoduleDiffType, SummaryDelta} from '../../types'
import {describe, it, expect} from '@github-ui/tests'

describe('SubmoduleDiff', () => {
  it('renders when added', () => {
    render(<SubmoduleDiff submodule={{...mockSubmoduleWithoutSummaries, status: 'ADDED', oldCommitOid: undefined}} />)

    expect(screen.getByText('Submodule added at')).toBeInTheDocument()
    expect(screen.getByRole('link', {name: /illuminati/})).toHaveAttribute(
      'href',
      'http://www.github.com/monalisa/illuminati',
    )
    expect(screen.getByRole('link', {name: /d552450/})).toHaveAttribute(
      'href',
      'http://www.github.com/monalisa/illuminati/tree/d552450188b7d9171d36327d8b7bd725e20a54cb',
    )
  })

  it('renders when deleted', () => {
    render(<SubmoduleDiff submodule={{...mockSubmoduleWithoutSummaries, status: 'DELETED', newCommitOid: undefined}} />)

    expect(screen.getByText('Submodule deleted from')).toBeInTheDocument()
    expect(screen.getByRole('link', {name: /illuminati/})).toHaveAttribute(
      'href',
      'http://www.github.com/monalisa/illuminati',
    )
    expect(screen.getByRole('link', {name: /e1da9b0/})).toHaveAttribute(
      'href',
      'http://www.github.com/monalisa/illuminati/tree/e1da9b0583d7d3fbc0676aa832808d91e49a03f2',
    )
  })

  it('renders when modified with summaries', () => {
    render(<SubmoduleDiff submodule={mockSubmodule} />)

    expect(screen.getByText('Submodule updated')).toBeInTheDocument()
    expect(screen.getByRole('link', {name: /illuminati/})).toHaveAttribute(
      'href',
      'http://www.github.com/monalisa/illuminati',
    )
    expect(screen.getByRole('link', {name: /8 files/})).toHaveAttribute(
      'href',
      'http://www.github.com/monalisa/illuminati/compare/e1da9b0583d7d3fbc0676aa832808d91e49a03f2...d552450188b7d9171d36327d8b7bd725e20a54cb',
    )

    // 8 summary items/links
    expect(screen.queryAllByRole('link', {name: /^(?!illuminati|8 files).*$/})).toHaveLength(8)
  })

  it('renders linkable when modified without summaries', () => {
    render(<SubmoduleDiff submodule={mockSubmoduleWithoutSummaries} />)

    expect(screen.getByText('Submodule updated')).toBeInTheDocument()
    expect(screen.getByRole('link', {name: /illuminati/})).toHaveAttribute(
      'href',
      'http://www.github.com/monalisa/illuminati',
    )
    expect(screen.getByRole('link', {name: /from e1da9b0 to d552450/})).toHaveAttribute(
      'href',
      'http://www.github.com/monalisa/illuminati/compare/e1da9b0583d7d3fbc0676aa832808d91e49a03f2...d552450188b7d9171d36327d8b7bd725e20a54cb',
    )

    // no summary items/links
    expect(screen.queryAllByRole('link', {name: /^(?!illuminati|from e1da9b0 to d552450).*$/})).toHaveLength(0)
  })

  it('renders when modified without summaries and not linkable', () => {
    render(<SubmoduleDiff submodule={{...mockSubmoduleWithoutSummaries, contentsUrl: ''}} />)

    expect(screen.getByText('Submodule updated from e1da9b0 to d552450')).toBeInTheDocument()
    expect(screen.getByRole('link', {name: /illuminati/})).toHaveAttribute(
      'href',
      'http://www.github.com/monalisa/illuminati',
    )

    // no summary items/links or compare link
    expect(screen.queryAllByRole('link', {name: /^(?!illuminati).*$/})).toHaveLength(0)
  })
})

describe('SubmoduleFileRow', () => {
  const defaultProps: SummaryDelta = {
    linesAdded: 10,
    linesDeleted: 5,
    path: 'test/path.js',
    pathDigest: 'digest123',
    status: 'MODIFIED' as const,
  }

  const defaultSubmoduleProps: SubmoduleDiffType = {
    basePath: 'test',
    contentsUrl: 'content-url',
    changedFiles: 1,
    newCommitOid: 'def',
    oldCommitOid: 'abc',
    status: 'MODIFIED',
    submoduleUrl: 'test-url',
    summary: [],
  }

  it('renders file path and status icon', () => {
    render(
      <SubmoduleDiff
        submodule={{
          ...defaultSubmoduleProps,
          summary: [defaultProps],
        }}
      />,
    )

    expect(screen.getByText('test/path.js')).toBeInTheDocument()
    expect(screen.getByText('+10')).toBeInTheDocument()
    expect(screen.getByText('-5')).toBeInTheDocument()
  })

  it('formats large numbers with k suffix', () => {
    render(
      <SubmoduleDiff
        submodule={{
          ...defaultSubmoduleProps,
          summary: [
            {
              ...defaultProps,
              linesAdded: 1500,
              linesDeleted: 2500,
            },
          ],
        }}
      />,
    )

    expect(screen.getByText('+1.5k')).toBeInTheDocument()
    expect(screen.getByText('-2.5k')).toBeInTheDocument()
  })

  it('links to correct compare URL with digest', () => {
    render(
      <SubmoduleDiff
        submodule={{
          ...defaultSubmoduleProps,
          summary: [defaultProps],
        }}
      />,
    )

    const link = screen.getByRole('link', {name: /test\/path\.js/})
    expect(link).toHaveAttribute('href', 'content-url/compare/abc...def#diff-digest123')
  })

  it('omits line count section when no lines changed', () => {
    render(
      <SubmoduleDiff
        submodule={{
          ...defaultSubmoduleProps,
          summary: [
            {
              ...defaultProps,
              linesAdded: 0,
              linesDeleted: 0,
            },
          ],
        }}
      />,
    )

    expect(screen.queryByText('+0')).not.toBeInTheDocument()
    expect(screen.queryByText('-0')).not.toBeInTheDocument()
  })
})

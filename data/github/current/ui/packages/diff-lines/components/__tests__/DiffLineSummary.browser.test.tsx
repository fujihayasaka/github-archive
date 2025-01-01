import {render, screen} from '@testing-library/react'
import {describe, expect, it} from '@github-ui/tests'

import DiffLineScreenReaderSummary from '../DiffLineScreenReaderSummary'
import {buildAnnotation, buildDiffLine, buildThread} from '../../test-utils/query-data'

describe('DiffLineSummary', () => {
  it('when the diffline has no markers, render nothing', () => {
    const diffLine = buildDiffLine({threads: [], annotations: []})

    render(<DiffLineScreenReaderSummary diffLine={diffLine} />)
    expect(screen.queryByTestId('pr-diffline-summary')).not.toBeInTheDocument()
  })

  it('when the diffline has threads, render "Code has comments. Press enter to view."', () => {
    const diffLine = buildDiffLine({threads: [buildThread({})], annotations: []})

    render(<DiffLineScreenReaderSummary diffLine={diffLine} />)
    expect(screen.getByText('Code has comments. Press enter to view.')).toBeInTheDocument()
  })

  it('when the diffline has annotations, render "Code has alerts. Press enter to view."', () => {
    const diffLine = buildDiffLine({threads: [], annotations: [buildAnnotation({})]})

    render(<DiffLineScreenReaderSummary diffLine={diffLine} />)
    expect(screen.getByText('Code has alerts. Press enter to view.')).toBeInTheDocument()
  })

  it('when the diffline has threads and annotations, render "Code has comments and alerts. Press enter to view."', () => {
    const diffLine = buildDiffLine({threads: [buildThread({})], annotations: [buildAnnotation({})]})

    render(<DiffLineScreenReaderSummary diffLine={diffLine} />)
    expect(screen.getByText('Code has comments and alerts. Press enter to view.')).toBeInTheDocument()
  })
})

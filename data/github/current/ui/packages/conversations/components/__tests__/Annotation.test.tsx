import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {buildAnnotation} from '../../test-utils/query-data'
import {DiffAnnotationLevels} from '../../types'
import {Annotation} from '../Annotation'

describe('Annotation', () => {
  test('renders basic annotation details', () => {
    const annotationTitle = 'my annotation title'
    const checkSuiteName = 'GitHub CI'
    const checkRunName = 'github-all-features'
    const annotationMessage = 'this is the annotation message'
    const appAvatarAltText = 'github avatar image'

    const annotation = buildAnnotation({
      annotationLevel: DiffAnnotationLevels.Failure,
      message: annotationMessage,
      title: annotationTitle,
      checkRun: {
        name: checkRunName,
        detailsUrl: 'http://github.localhost/monalisa/smile/actions/runs/1/job/1',
      },
      checkSuiteName,
      appAvatarAltText,
      appAvatarUrl: 'http://alambic.github.localhost/avatars/u/2',
    })
    render(<Annotation annotation={annotation} />)
    expect(screen.getByText('Check failure')).toBeInTheDocument()
    expect(screen.getByText(annotationTitle)).toBeInTheDocument()
    expect(screen.getByText(checkRunName)).toBeInTheDocument()
    expect(screen.getByText(checkSuiteName)).toBeInTheDocument()
    expect(screen.getByText(annotationMessage)).toBeInTheDocument()
    expect(screen.getByText('View details')).toBeInTheDocument()
    expect(screen.getByAltText(appAvatarAltText)).toBeInTheDocument()
  })

  test('renders failure', () => {
    const annotation = buildAnnotation({
      annotationLevel: DiffAnnotationLevels.Failure,
    })
    render(<Annotation annotation={annotation} />)
    expect(screen.getByText('Check failure')).toBeInTheDocument()
  })

  test('renders warning', () => {
    const annotation = buildAnnotation({
      annotationLevel: DiffAnnotationLevels.Warning,
    })
    render(<Annotation annotation={annotation} />)
    expect(screen.getByText('Check warning')).toBeInTheDocument()
  })

  test('renders notice', () => {
    const annotation = buildAnnotation({
      annotationLevel: DiffAnnotationLevels.Notice,
    })
    render(<Annotation annotation={annotation} />)
    expect(screen.getByText('Check notice')).toBeInTheDocument()
  })
})

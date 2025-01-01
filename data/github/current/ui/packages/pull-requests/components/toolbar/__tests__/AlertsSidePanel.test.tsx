import type {DiffAnnotation} from '@github-ui/conversations'
import {DiffAnnotationLevels} from '@github-ui/conversations'
import {render} from '@github-ui/react-core/test-utils'
import {screen, waitFor} from '@testing-library/react'
import {useRef} from 'react'

import {AlertsSidePanel} from '../AlertsSidePanel'
import {buildAnnotation} from '@github-ui/conversations/test-utils'
import {getFilesRoutePayload} from '../../../test-utils/files-changed/files-mock-data'

const DefaultDiffAnnotationData = {
  FAILURE: {
    annotationLevel: DiffAnnotationLevels.Failure,
    message:
      'Minitest::Assertion:\n\n        The following CSS classes were used in class attributes but have no style rules referencing them:\n\n        Class name                     Seen in\n        ======================================\n        text-mono                      app/views/checks/_checks_summary.html.erb\n        /github/file.rb:84\n',
    title: 'QueryContext test succeeds',
  },
  NOTICE: {
    annotationLevel: DiffAnnotationLevels.Notice,
    message: 'An interesting thing about this is X.',
    title: 'RenderContext test renders correct object',
  },
  WARNING: {
    annotationLevel: DiffAnnotationLevels.Warning,
    message: 'This might be problematic in the future because X.',
    title: 'MemberContext test does not include member',
  },
}

// eslint-disable-next-line @eslint-react/no-unstable-default-props
function TestComponent({diffAnnotations = []}: {diffAnnotations?: DiffAnnotation[]}) {
  return (
    <AlertsSidePanel
      annotations={diffAnnotations}
      isOpen
      returnFocusRef={useRef(null)}
      onClose={jest.fn}
      pageLimits={getFilesRoutePayload().pageLimits}
    />
  )
}

test('renders annotation details for every annotation', () => {
  const checkSuiteName = 'check-suite-name'
  const checkRunName = 'check-run-name'
  const warning = buildAnnotation({
    annotationLevel: DiffAnnotationLevels.Warning,
    checkSuiteName,
    message: DefaultDiffAnnotationData.WARNING.message,
    title: DefaultDiffAnnotationData.WARNING.title,
    checkRun: {detailsUrl: 'http://github.localhost/monalisa/smile/actions/runs/1/job/1', name: checkRunName},
  })
  const notice = buildAnnotation({
    annotationLevel: DiffAnnotationLevels.Notice,
    checkSuiteName,
    message: DefaultDiffAnnotationData.NOTICE.message,
    title: DefaultDiffAnnotationData.NOTICE.title,
    checkRun: {detailsUrl: 'http://github.localhost/monalisa/smile/actions/runs/1/job/2', name: checkRunName},
  })
  const failure = buildAnnotation({
    annotationLevel: DiffAnnotationLevels.Failure,
    checkSuiteName,
    message: 'Failed due to code conflict',
    title: DefaultDiffAnnotationData.FAILURE.title,
    checkRun: {detailsUrl: 'http://github.localhost/monalisa/smile/actions/runs/1/job/3', name: checkRunName},
  })

  render(<TestComponent diffAnnotations={[warning, notice, failure]} />)

  // Assert that all 3 annotation links are rendered
  const viewDetailsLinks = screen.getAllByRole('link', {name: 'View details'})
  expect(viewDetailsLinks).toHaveLength(3)
  expect(viewDetailsLinks.map(link => (link as HTMLLinkElement).href)).toEqual([
    warning.checkRun.detailsUrl,
    notice.checkRun.detailsUrl,
    failure.checkRun.detailsUrl,
  ])

  // Assert unique warning annotation info is rendered
  expect(screen.getByText(warning.message)).toBeInTheDocument()
  expect(screen.getByText('Check warning')).toBeInTheDocument()
  expect(screen.getByText(warning.title)).toBeInTheDocument()

  // Assert unique notice annotation info is rendered
  expect(screen.getByText(notice.message)).toBeInTheDocument()
  expect(screen.getByText('Check notice')).toBeInTheDocument()
  expect(screen.getByText(notice.title)).toBeInTheDocument()

  // Assert unique failure annotation info is rendered
  expect(screen.getByText(failure.message)).toBeInTheDocument()
  expect(screen.getByText('Check failure')).toBeInTheDocument()
  expect(screen.getByText(failure.title)).toBeInTheDocument()

  // Assert that all 3 check run and check suite names are rendered
  // these are not unique as we are not overriding defaults in buildAnnotation
  expect(screen.getAllByText(checkRunName)).toHaveLength(3)
  expect(screen.getAllByText(checkSuiteName)).toHaveLength(3)
})

test('only renders filtered annotations matching annotation level', async () => {
  const matched = buildAnnotation({annotationLevel: DiffAnnotationLevels.Warning})
  const filtered = buildAnnotation({annotationLevel: DiffAnnotationLevels.Notice})
  const {user} = render(<TestComponent diffAnnotations={[matched, filtered]} />)

  // Assert that both annotations are being rendered before user filters
  expect(screen.getByText('Check warning')).toBeInTheDocument()
  expect(screen.getByText('Check notice')).toBeInTheDocument()

  const filterInput = screen.getByPlaceholderText('Filter alerts…')
  await user.type(filterInput, 'w')

  // Assert that only the warning annotation is being rendered with "w" text filter

  await user.type(filterInput, 'arning')

  // Assert that only the warning annotation is being rendered with "warning" text filter
  expect(screen.getByText('Check warning')).toBeInTheDocument()
  expect(screen.queryByText('Check notice')).not.toBeInTheDocument()

  await user.type(filterInput, '!')

  // Assert that no annotations are being rendered with "warning!" text filter
  expect(screen.queryByText('Check warning')).not.toBeInTheDocument()
  expect(screen.queryByText('Check notice')).not.toBeInTheDocument()
})

test('only renders filtered annotations matching annotation message', async () => {
  const {user} = render(
    <TestComponent diffAnnotations={[buildAnnotation({message: 'match'}), buildAnnotation({message: 'matched'})]} />,
  )

  // Assert that both annotations are being rendered before user filters
  expect(screen.getByText('match')).toBeInTheDocument()
  expect(screen.getByText('matched')).toBeInTheDocument()

  const filterInput = screen.getByPlaceholderText('Filter alerts…')
  await user.type(filterInput, 'z')

  // Assert that both annotations are not being rendered as "z" is not text matching "match" or "matched"
  expect(screen.queryByText('match')).not.toBeInTheDocument()
  expect(screen.queryByText('matched')).not.toBeInTheDocument()

  await user.clear(filterInput)

  // Assert that both annotations are being rendered because filter input is cleared
  expect(screen.getByText('match')).toBeInTheDocument()
  expect(screen.getByText('matched')).toBeInTheDocument()

  await user.type(filterInput, 'm')

  // Assert that both annotations are being rendered as "m" is matching "match" or "matched"
  expect(screen.getByText('match')).toBeInTheDocument()
  expect(screen.getByText('matched')).toBeInTheDocument()

  await user.type(filterInput, 'atch')

  // Assert that both annotations are being rendered as "match" is matching "match" or "matched"
  expect(screen.getByText('match')).toBeInTheDocument()
  expect(screen.getByText('matched')).toBeInTheDocument()

  await user.type(filterInput, 'e')

  // Assert that only 1 annotation is being rendered as "matche" is only matching on "matched"
  expect(screen.queryByText('match')).not.toBeInTheDocument()
  expect(screen.getByText('matched')).toBeInTheDocument()
})

test('only renders filtered annotations matching annotation path', async () => {
  const {user} = render(
    <TestComponent diffAnnotations={[buildAnnotation({path: 'a.tsx'}), buildAnnotation({path: 'b.rb'})]} />,
  )

  // Assert that both annotations are being rendered before user filters
  expect(screen.getByText('a.tsx')).toBeInTheDocument()
  expect(screen.getByText('b.rb')).toBeInTheDocument()

  const filterInput = screen.getByPlaceholderText('Filter alerts…')
  await user.type(filterInput, 'z.txt')

  // Assert that both annotations are not being rendered as "z.txt" is not text matching "a.tsx" or "b.rb"
  expect(screen.queryByText('a.tsx')).not.toBeInTheDocument()
  expect(screen.queryByText('b.rb')).not.toBeInTheDocument()

  await user.clear(filterInput)

  // Assert that both annotations are being rendered because filter input is cleared
  expect(screen.getByText('a.tsx')).toBeInTheDocument()
  expect(screen.getByText('b.rb')).toBeInTheDocument()

  await user.type(filterInput, 'a.ts')

  // Assert that only 1 annotation is being rendered as "a.ts" is only matching on "a.tsx"
  expect(screen.getByText('a.tsx')).toBeInTheDocument()
  expect(screen.queryByText('b.rb')).not.toBeInTheDocument()

  await user.type(filterInput, 'x')

  // Assert that only 1 annotation is being rendered as "a.tsx" is only matching on "a.tsx"
  expect(screen.getByText('a.tsx')).toBeInTheDocument()
  expect(screen.queryByText('b.rb')).not.toBeInTheDocument()

  await user.type(filterInput, '.test')

  // Assert that both annotations are not being rendered as "a.tsx.test" is not text matching "a.tsx" or "b.rb"
  expect(screen.queryByText('a.tsx')).not.toBeInTheDocument()
  expect(screen.queryByText('b.rb')).not.toBeInTheDocument()
})

test('only renders filtered annotations matching annotation title', async () => {
  const {user} = render(
    <TestComponent diffAnnotations={[buildAnnotation({title: 'CTX#1'}), buildAnnotation({title: 'Test#2'})]} />,
  )

  // Assert that both annotations are being rendered before user filters
  expect(screen.getByText('CTX#1')).toBeInTheDocument()
  expect(screen.getByText('Test#2')).toBeInTheDocument()

  const filterInput = screen.getByPlaceholderText('Filter alerts…')
  await user.type(filterInput, 'Context#Fun')

  // Assert that both annotations are not being rendered as "Context#Fun" is not text matching "CTX#1" or "Test#2"
  expect(screen.queryByText('CTX#1')).not.toBeInTheDocument()
  expect(screen.queryByText('Test#2')).not.toBeInTheDocument()

  await user.clear(filterInput)

  // Assert that both annotations are being rendered because filter input is cleared
  expect(screen.getByText('CTX#1')).toBeInTheDocument()
  expect(screen.getByText('Test#2')).toBeInTheDocument()

  await user.type(filterInput, '#')

  // Assert that both annotations are being rendered as "#" is matching on "CTX#1" and "Test#2"
  expect(screen.getByText('CTX#1')).toBeInTheDocument()
  expect(screen.getByText('Test#2')).toBeInTheDocument()

  await user.type(filterInput, '1')

  // Assert that only 1 annotation is being rendered as "#1" is only matching on "CTX#1"
  expect(screen.getByText('CTX#1')).toBeInTheDocument()
  expect(screen.queryByText('Test#2')).not.toBeInTheDocument()

  await user.type(filterInput, '2')

  // Assert that both annotations are not being rendered as "#12" is not text matching "CTX#1" or "Test#2"
  expect(screen.queryByText('CTX#1')).not.toBeInTheDocument()
  expect(screen.queryByText('Test#2')).not.toBeInTheDocument()
})

test('only renders filtered annotations matching annotation check run name', async () => {
  const {user} = render(
    <TestComponent
      diffAnnotations={[
        buildAnnotation({
          checkRun: {
            name: 'eslint-tester',
            detailsUrl: 'eslint-tester/1/job',
          },
        }),
        buildAnnotation({
          checkRun: {
            name: 'jest-tsc',
            detailsUrl: 'jest-tsc/1/job',
          },
        }),
      ]}
    />,
  )

  // Assert that both annotations are being rendered before user filters
  expect(screen.getByText('jest-tsc')).toBeInTheDocument()
  expect(screen.getByText('eslint-tester')).toBeInTheDocument()

  const filterInput = screen.getByPlaceholderText('Filter alerts…')
  await user.type(filterInput, 'ruby-sorbet')

  // Assert that both annotations are not being rendered as "ruby-sorbet" is not text matching "jest-tsc" or "eslint-tester"
  expect(screen.queryByText('jest-tsc')).not.toBeInTheDocument()
  expect(screen.queryByText('eslint-tester')).not.toBeInTheDocument()

  await user.clear(filterInput)

  // Assert that both annotations are being rendered because filter input is cleared
  expect(screen.getByText('jest-tsc')).toBeInTheDocument()
  expect(screen.getByText('eslint-tester')).toBeInTheDocument()

  await user.type(filterInput, 'es')

  // Assert that both annotations are being rendered as "es" is matching on "eslint-tester" and "jest"
  expect(screen.getByText('jest-tsc')).toBeInTheDocument()
  expect(screen.getByText('eslint-tester')).toBeInTheDocument()

  await user.type(filterInput, 't-t')

  // Assert that only 1 annotation is being rendered as "est-t" is only matching on "jest-tsc"
  expect(screen.getByText('jest-tsc')).toBeInTheDocument()
  expect(screen.queryByText('eslint-tester')).not.toBeInTheDocument()

  await user.type(filterInput, 't-tsc!')

  // Assert that both annotations are not being rendered as "est-tsc!" is not text matching on "jest-tsc" or "eslint-tester"
  expect(screen.queryByText('jest-tsc')).not.toBeInTheDocument()
  expect(screen.queryByText('eslint-tester')).not.toBeInTheDocument()
})

test('only renders filtered annotations matching annotation check suite app name', async () => {
  const {user} = render(
    <TestComponent
      diffAnnotations={[
        buildAnnotation({checkSuiteName: 'env-production'}),
        buildAnnotation({checkSuiteName: 'env-development'}),
      ]}
    />,
  )

  // Assert that both annotations are being rendered before user filters
  expect(screen.getByText('env-production')).toBeInTheDocument()
  expect(screen.getByText('env-development')).toBeInTheDocument()

  const filterInput = screen.getByPlaceholderText('Filter alerts…')
  await user.type(filterInput, 'env-t')

  // Assert that both annotations are not being rendered as "env-t" is not text matching "env-production" or "env-development"
  expect(screen.queryByText('env-production')).not.toBeInTheDocument()
  expect(screen.queryByText('env-development')).not.toBeInTheDocument()

  await user.clear(filterInput)

  // Assert that both annotations are being rendered because filter input is cleared
  expect(screen.getByText('env-production')).toBeInTheDocument()
  expect(screen.getByText('env-development')).toBeInTheDocument()

  await user.type(filterInput, 'env-')

  // Assert that both annotations are being rendered as "env-" is matching on "env-development" and "jest"
  expect(screen.getByText('env-production')).toBeInTheDocument()
  expect(screen.getByText('env-development')).toBeInTheDocument()

  await user.type(filterInput, 'p')

  // Assert that only 1 annotation is being rendered as "est-p" is only matching on "env-production"
  expect(screen.getByText('env-production')).toBeInTheDocument()
  expect(screen.queryByText('env-development')).not.toBeInTheDocument()

  await user.type(filterInput, 'roduction!')

  // Assert that both annotations are not being rendered as "env-production!" is not text matching on "env-production" or "env-development"
  expect(screen.queryByText('env-production')).not.toBeInTheDocument()
  expect(screen.queryByText('env-development')).not.toBeInTheDocument()
})

test('only renders filtered annotations matching annotation check suite name', async () => {
  const prodCheckSuite = 'env-production'
  const devCheckSuite = 'env-development'

  const {user} = render(
    <TestComponent
      diffAnnotations={[
        buildAnnotation({
          checkSuiteName: prodCheckSuite,
        }),
        buildAnnotation({
          checkSuiteName: devCheckSuite,
        }),
      ]}
    />,
  )

  // Assert that both annotations are being rendered before user filters
  expect(screen.getByText(prodCheckSuite)).toBeInTheDocument()
  expect(screen.getByText(devCheckSuite)).toBeInTheDocument()

  const filterInput = screen.getByPlaceholderText('Filter alerts…')
  await user.type(filterInput, 'env-t')

  // Assert that both annotations are not being rendered as "env-t" is not text matching "env-development" or "environemnt-production"
  expect(screen.queryByText(prodCheckSuite)).not.toBeInTheDocument()
  expect(screen.queryByText(devCheckSuite)).not.toBeInTheDocument()

  await user.clear(filterInput)

  // Assert that both annotations are being rendered because filter input is cleared
  expect(screen.getByText(prodCheckSuite)).toBeInTheDocument()
  expect(screen.getByText(devCheckSuite)).toBeInTheDocument()

  await user.type(filterInput, 'env-')

  // Assert that both annotations are being rendered as "env-" is matching on "env-development" and "environment-production"
  expect(screen.getByText(prodCheckSuite)).toBeInTheDocument()
  expect(screen.getByText(devCheckSuite)).toBeInTheDocument()

  await user.type(filterInput, 'p')

  // Assert that only 1 annotation is being rendered as "env-p" is only matching on "env-production"
  expect(screen.getByText(prodCheckSuite)).toBeInTheDocument()
  expect(screen.queryByText(devCheckSuite)).not.toBeInTheDocument()

  await user.type(filterInput, 'roduction!')

  // Assert that both annotations are not being rendered as "env-production!" is not text matching on "env-development" or "environment-production"
  expect(screen.queryByText(prodCheckSuite)).not.toBeInTheDocument()
  expect(screen.queryByText(devCheckSuite)).not.toBeInTheDocument()
})

test('announces via live region updates', async () => {
  const matched = buildAnnotation({annotationLevel: DiffAnnotationLevels.Warning})
  const filtered = buildAnnotation({annotationLevel: DiffAnnotationLevels.Notice})
  const {user} = render(<TestComponent diffAnnotations={[matched, filtered]} />)

  // Assert that both annotations are being rendered before user filters
  expect(screen.getByText('Check warning')).toBeInTheDocument()
  expect(screen.getByText('Check notice')).toBeInTheDocument()

  const filterInput = screen.getByPlaceholderText('Filter alerts…')
  await user.type(filterInput, 'w')

  expect(screen.getByText('Check warning')).toBeInTheDocument()
  expect(screen.queryByText('Check notice')).not.toBeInTheDocument()

  // Assert that live region announces number of results
  await waitFor(() => {
    expect(screen.getByText('1 alert')).toBeInTheDocument()
  })

  await user.type(filterInput, '!')

  expect(screen.queryByText('Check warning')).not.toBeInTheDocument()
  expect(screen.queryByText('Check notice')).not.toBeInTheDocument()

  // Assert that live region announces empty reults
  await waitFor(() => {
    expect(screen.getByText('No alerts found')).toBeInTheDocument()
  })
})

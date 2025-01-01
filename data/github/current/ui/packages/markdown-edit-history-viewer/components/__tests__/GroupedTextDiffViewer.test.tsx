import {createRelayMockEnvironment} from '@github-ui/relay-test-utils/RelayMockEnvironment'
import {ThemeProvider} from '@primer/react'
import {render, screen} from '@testing-library/react'
import {Suspense} from 'react'
import {RelayEnvironmentProvider} from 'react-relay'
import type {RelayMockEnvironment} from 'relay-test-utils/lib/RelayModernMockEnvironment'

import {GroupedTextDiffViewer} from '../GroupedTextDiffViewer'

function TestComponent({
  environment,
  before,
  after,
}: {
  environment: RelayMockEnvironment
  before: string | undefined
  after: string | undefined
}) {
  return (
    <RelayEnvironmentProvider environment={environment}>
      <ThemeProvider>
        <Suspense fallback="...Loading">
          <GroupedTextDiffViewer before={before} after={after} />
        </Suspense>
      </ThemeProvider>
    </RelayEnvironmentProvider>
  )
}

test('renders no changes', async () => {
  const before = 'This is a test'
  const after = 'This is a test'
  const {environment} = createRelayMockEnvironment()
  render(<TestComponent environment={environment} before={before} after={after} />)

  const beforeText = screen.getByText('This is a test')
  expect(beforeText).toBeInTheDocument()
})

test('renders an addition and deletion', async () => {
  const before = 'This is a test'
  const after = 'Completely different'
  const {environment} = createRelayMockEnvironment()
  render(<TestComponent environment={environment} before={before} after={after} />)

  const beforeText = screen.getByText('This is a test')
  const afterText = screen.getByText('Completely different')
  const deletedStartText = screen.getByText('[-]')
  const deletedEndText = screen.getByText('[/-]')
  const addedStartText = screen.getByText('[+]')
  const addedEndText = screen.getByText('[/+]')
  expect(beforeText).toBeInTheDocument()
  expect(afterText).toBeInTheDocument()
  expect(deletedStartText).toBeInTheDocument()
  expect(deletedEndText).toBeInTheDocument()
  expect(addedStartText).toBeInTheDocument()
  expect(addedEndText).toBeInTheDocument()
  expect(addedStartText.compareDocumentPosition(afterText)).toBe(Node.DOCUMENT_POSITION_FOLLOWING)
  expect(addedEndText.compareDocumentPosition(afterText)).toBe(Node.DOCUMENT_POSITION_PRECEDING)
  expect(deletedStartText.compareDocumentPosition(beforeText)).toBe(Node.DOCUMENT_POSITION_FOLLOWING)
  expect(deletedEndText.compareDocumentPosition(beforeText)).toBe(Node.DOCUMENT_POSITION_PRECEDING)
})

test('renders an unchanged in the middle', async () => {
  const before = 'This is a test'
  const after = 'What is a change'
  const {environment} = createRelayMockEnvironment()
  render(<TestComponent environment={environment} before={before} after={after} />)

  const beforeText1 = screen.getByText('This')
  const afterText1 = screen.getByText('What')
  const middleText = screen.getByText('is a')
  const beforeText2 = screen.getByText('test')
  const afterText2 = screen.getByText('change')
  const deletedStartText = screen.getAllByText('[-]')
  const deletedEndText = screen.getAllByText('[/-]')
  const addedStartText = screen.getAllByText('[+]')
  const addedEndText = screen.getAllByText('[/+]')

  expect(addedStartText.length).toBe(2)
  expect(addedEndText.length).toBe(2)
  expect(deletedStartText.length).toBe(2)
  expect(deletedEndText.length).toBe(2)

  expect(beforeText1).toBeInTheDocument()
  expect(afterText1).toBeInTheDocument()
  expect(middleText).toBeInTheDocument()
  expect(beforeText2).toBeInTheDocument()
  expect(afterText2).toBeInTheDocument()
  expect(deletedStartText[0]).toBeInTheDocument()
  expect(addedStartText[0]).toBeInTheDocument()
  expect(deletedStartText[1]).toBeInTheDocument()
  expect(addedStartText[1]).toBeInTheDocument()
  expect(deletedEndText[0]).toBeInTheDocument()
  expect(addedEndText[0]).toBeInTheDocument()
  expect(deletedEndText[1]).toBeInTheDocument()
  expect(addedEndText[1]).toBeInTheDocument()
  expect(addedStartText[0]!.compareDocumentPosition(afterText1)).toBe(Node.DOCUMENT_POSITION_FOLLOWING)
  expect(addedEndText[0]!.compareDocumentPosition(afterText1)).toBe(Node.DOCUMENT_POSITION_PRECEDING)
  expect(deletedStartText[0]!.compareDocumentPosition(beforeText1)).toBe(Node.DOCUMENT_POSITION_FOLLOWING)
  expect(deletedEndText[0]!.compareDocumentPosition(beforeText1)).toBe(Node.DOCUMENT_POSITION_PRECEDING)
  expect(addedStartText[1]!.compareDocumentPosition(afterText2)).toBe(Node.DOCUMENT_POSITION_FOLLOWING)
  expect(addedEndText[1]!.compareDocumentPosition(afterText2)).toBe(Node.DOCUMENT_POSITION_PRECEDING)
  expect(deletedStartText[1]!.compareDocumentPosition(beforeText2)).toBe(Node.DOCUMENT_POSITION_FOLLOWING)
  expect(deletedEndText[1]!.compareDocumentPosition(beforeText2)).toBe(Node.DOCUMENT_POSITION_PRECEDING)
  expect(deletedEndText[0]!.compareDocumentPosition(middleText)).toBe(Node.DOCUMENT_POSITION_FOLLOWING)
  expect(addedEndText[1]!.compareDocumentPosition(middleText)).toBe(Node.DOCUMENT_POSITION_PRECEDING)
})

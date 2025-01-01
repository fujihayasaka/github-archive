import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {getPromptAppPayload} from '../../../test-utils/mock-data'
import {PromptRoute} from '../PromptRoute'
import {Route, Routes} from 'react-router-dom'
import type {PromptAppPayload} from '../types'

const PROMPT_PATH = '/github-owner/github-repo/models/prompt'
const EDIT_PATH = '/github-owner/github-repo/models/prompt/edit/branchname/yada'
const COMPARE_PATH = '/github-owner/github-repo/models/prompt/compare/branchname/yada'

function renderWithRoute(pathname: string, appPayload: PromptAppPayload) {
  return render(
    <Routes>
      <Route path="/:owner/:repo/models/prompt" element={<PromptRoute />} />
      <Route path="/:owner/:repo/models/prompt/edit/:branch/*" element={<PromptRoute />} />
      <Route path="/:owner/:repo/models/prompt/edit/:branch/*" element={<PromptRoute />} />
      <Route path="/:owner/:repo/models/prompt/compare/:branch/*" element={<PromptRoute />} />
    </Routes>,
    {
      appPayload,
      pathname,
    },
  )
}

test('Renders the Models Prompt Edit route', () => {
  const appPayload = getPromptAppPayload()
  renderWithRoute('/github-owner/github-repo/models/prompt/edit/branchname/yada', appPayload)

  expect(screen.getByRole('heading', {level: 2, name: 'Iterate on your prompt'})).toBeInTheDocument()
})

test('Error for invalid prompt frontmatter value', () => {
  const appPayload = getPromptAppPayload()
  appPayload.payload.prompt = `name: 123`
  renderWithRoute(PROMPT_PATH, appPayload)

  expect(screen.getByText(/We could not load your prompt/)).toBeInTheDocument()
})

describe('Prompt edit view', () => {
  test('Renders the prompt edit view', () => {
    const appPayload = getPromptAppPayload()
    renderWithRoute(EDIT_PATH, appPayload)

    expect(screen.getByRole('heading', {level: 2, name: 'Iterate on your prompt'})).toBeInTheDocument()
  })

  test('Renders commit button for user write access', () => {
    const appPayload = getPromptAppPayload({payload: {canEdit: true}})
    renderWithRoute(EDIT_PATH, appPayload)

    expect(screen.getByRole('button', {name: 'Commit changes'})).toBeInTheDocument()
  })

  test('Does not render commit button for user read access', () => {
    const appPayload = getPromptAppPayload({payload: {canEdit: false}})
    renderWithRoute(EDIT_PATH, appPayload)

    expect(screen.queryByRole('button', {name: 'Commit changes'})).not.toBeInTheDocument()
  })

  test('Prefills the input variable with the first input', async () => {
    const promptWithInput = `name: 'Input Variable Test Prompt'
description: 'This is a test prompt'
model: 'gpt-4'
messages:
  - role: system
    content: 'System prompt'
  - role: user
    content: 'User prompt that references {{input}}'
testData:
  - input: foobar
    expected: baz`

    const appPayload = getPromptAppPayload()
    appPayload.payload.prompt = promptWithInput

    const {user} = renderWithRoute(EDIT_PATH, appPayload)

    await user.click(screen.queryByRole('button', {name: 'Variables'})!)

    const inputTextArea = screen.getByDisplayValue('foobar')
    expect(inputTextArea).toBeInTheDocument()
  })
})

describe('Prompt compare view', () => {
  test('Renders the prompt compare view', () => {
    const appPayload = getPromptAppPayload()
    renderWithRoute(COMPARE_PATH, appPayload)

    expect(screen.queryByRole('button', {name: 'Compare'})).toHaveAttribute('aria-current', 'true')
  })

  test('Renders commit button for user write access', () => {
    const appPayload = getPromptAppPayload({payload: {canEdit: true}})
    renderWithRoute(COMPARE_PATH, appPayload)

    expect(screen.getByRole('button', {name: 'Commit changes'})).toBeInTheDocument()
  })

  test('Does not render commit button for user read access', () => {
    const appPayload = getPromptAppPayload({payload: {canEdit: false}})
    renderWithRoute(COMPARE_PATH, appPayload)

    expect(screen.queryByRole('button', {name: 'Commit changes'})).not.toBeInTheDocument()
  })
})

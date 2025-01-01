import {screen} from '@testing-library/react'
import {getDefaultConfig} from '../utils/option-config'
import {IssueCreateContextProvider} from '../contexts/IssueCreateContext'

import {render} from '@github-ui/react-core/test-utils'
import {TemplateListPaneFooter} from '../TemplateListPaneFooter'

const setup = () => {
  return render(
    <IssueCreateContextProvider optionConfig={getDefaultConfig()} preselectedData={undefined}>
      <TemplateListPaneFooter />
    </IssueCreateContextProvider>,
  )
}

test('renders the link to Copilot with create issue prompt', () => {
  setup()

  expect(
    screen.getAllByText(
      (_, element) => element?.textContent === 'Save time by creating issues with Copilot. Get started.',
    ),
  ).not.toBeNull()
  expect(screen.getByRole('link', {name: 'Get started.'})).toHaveAttribute(
    'href',
    new URL('/copilot?prompt=Create an issue to ....', window.location.origin).toString(),
  )
})

import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {PlaygroundCodeLanguage} from '../PlaygroundCodeLanguage'
import {mockGettingStarted} from '../../__tests__/mocks'
import {mockPlaygroundState} from '../GettingStartedDialog/__tests__/mocks'
import {PlaygroundStateProvider} from '../../../../contexts/PlaygroundStateContext'
import type {JSX} from 'react/jsx-runtime'

const selectedSDK = 'azure-ai-inference'

describe('PlaygroundCodeLanguage', () => {
  it('renders dropdown with all the available languages and the selected language', async () => {
    const {user} = renderComponent(<PlaygroundCodeLanguage gettingStarted={mockGettingStarted} />, 'python')

    const dropdownButton = screen.getByTestId('playground-language-button')
    expect(dropdownButton).toBeInTheDocument()
    expect(screen.getByText('Python')).toBeInTheDocument()

    await user.click(dropdownButton)

    const javascriptOption = screen.getByRole('menuitemradio', {name: 'JavaScript'})
    expect(javascriptOption).toBeInTheDocument()
    expect(javascriptOption).not.toBeChecked()

    const pythonOption = screen.getByRole('menuitemradio', {name: 'Python'})
    expect(pythonOption).toBeInTheDocument()
    expect(pythonOption).toBeChecked()

    const goOption = screen.getByRole('menuitemradio', {name: 'Go'})
    expect(goOption).toBeInTheDocument()
    expect(goOption).not.toBeChecked()

    const csharpOption = screen.getByRole('menuitemradio', {name: 'C#'})
    expect(csharpOption).toBeInTheDocument()
    expect(csharpOption).not.toBeChecked()
  })
})

function renderComponent(component: JSX.Element, selectedLanguage: string) {
  const stateValue = mockPlaygroundState({selectedLanguage, selectedSDK})
  return render(<PlaygroundStateProvider state={stateValue}>{component}</PlaygroundStateProvider>)
}

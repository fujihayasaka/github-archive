import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {PlaygroundCodeLanguage} from '../PlaygroundCodeLanguage'
import {mockGettingStarted} from '../../__tests__/mocks'
import {mockPlaygroundState} from '../GettingStartedDialog/__tests__/mocks'
import {PlaygroundStateProvider} from '../../../../contexts/PlaygroundStateContext'
import type {JSX} from 'react/jsx-runtime'

const mockHandleSelectedLanguage = jest.fn().mockName('handleSelectedLanguage')

describe('PlaygroundCodeLanguage', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  it('renders dropdown with all the available languages and the selected language', async () => {
    const {user} = renderComponent(
      <PlaygroundCodeLanguage
        gettingStarted={mockGettingStarted}
        preferredLanguage="python"
        handleSelectLanguage={mockHandleSelectedLanguage}
      />,
    )

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
    expect(mockHandleSelectedLanguage).not.toHaveBeenCalled()

    await user.click(csharpOption)

    expect(mockHandleSelectedLanguage).toHaveBeenCalledWith('csharp')
  })

  it('allows changing language option', async () => {
    const {user} = render(
      <PlaygroundCodeLanguage
        gettingStarted={mockGettingStarted}
        preferredLanguage="js"
        handleSelectLanguage={mockHandleSelectedLanguage}
      />,
    )
    const dropdownButton = screen.getByTestId('playground-language-button')
    expect(dropdownButton).toBeInTheDocument()
    expect(screen.getByText('JavaScript')).toBeInTheDocument()

    await user.click(dropdownButton)

    const javascriptOption = screen.getByRole('menuitemradio', {name: 'JavaScript'})
    expect(javascriptOption).toBeInTheDocument()
    expect(javascriptOption).toBeChecked()

    const pythonOption = screen.getByRole('menuitemradio', {name: 'Python'})
    expect(pythonOption).toBeInTheDocument()
    expect(pythonOption).not.toBeChecked()

    await user.click(pythonOption)

    expect(mockHandleSelectedLanguage).toHaveBeenCalledWith('python')
  })

  it('does not render when preferredLanguage is an empty string', () => {
    const gettingStarted = Object.assign({}, mockGettingStarted)
    render(
      <PlaygroundCodeLanguage
        gettingStarted={gettingStarted}
        preferredLanguage=""
        handleSelectLanguage={mockHandleSelectedLanguage}
      />,
    )
    expect(screen.queryByTestId('playground-language-button')).not.toBeInTheDocument()
  })

  it('does not render when there is no available snippet', () => {
    const gettingStarted = Object.assign({}, mockGettingStarted)
    render(
      <PlaygroundCodeLanguage
        gettingStarted={gettingStarted}
        preferredLanguage="php"
        handleSelectLanguage={mockHandleSelectedLanguage}
      />,
    )
    expect(screen.queryByTestId('playground-language-button')).not.toBeInTheDocument()
  })
})

function renderComponent(component: JSX.Element) {
  const stateValue = mockPlaygroundState()

  return render(<PlaygroundStateProvider state={stateValue}>{component}</PlaygroundStateProvider>)
}

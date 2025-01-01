import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {ChatPagingComponent} from '../ChatPagingComponent'

it('renders the paging component', async () => {
  render(<ChatPagingComponent currentPage={1} totalPages={4} onPrev={() => {}} onNext={() => {}} isUserMessage />)

  expect(await screen.findByRole('button', {name: 'Previous Response'})).toBeInTheDocument()
  expect(await screen.findByText('1/4')).toBeInTheDocument()
  expect(await screen.findByRole('button', {name: 'Next Response'})).toBeInTheDocument()
})

describe('parameter validation', () => {
  it('throws an error if currentPage is < 1', () => {
    const consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation()

    expect(() =>
      render(<ChatPagingComponent currentPage={0} totalPages={4} onPrev={() => {}} onNext={() => {}} isUserMessage />),
    ).toThrow('currentPage must be greater than or equal to 1')

    consoleErrorSpy.mockRestore()
  })

  it('throws an error if totalPages is < 1', () => {
    const consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation()

    expect(() =>
      render(<ChatPagingComponent currentPage={1} totalPages={0} onPrev={() => {}} onNext={() => {}} isUserMessage />),
    ).toThrow('totalPages must be greater than or equal to 1')

    consoleErrorSpy.mockRestore()
  })

  it('throws an error if currentPage is > totalPages>', () => {
    const consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation()

    expect(() =>
      render(<ChatPagingComponent currentPage={5} totalPages={4} onPrev={() => {}} onNext={() => {}} isUserMessage />),
    ).toThrow('currentPage must be less than or equal to totalPages')

    consoleErrorSpy.mockRestore()
  })
})

describe('page indicator', () => {
  it('displays the current page and total pages', async () => {
    render(<ChatPagingComponent currentPage={2} totalPages={5} onPrev={() => {}} onNext={() => {}} isUserMessage />)

    expect(await screen.findByText('2/5')).toBeInTheDocument()
  })
})

describe('onPrev', () => {
  it('is called when previous arrow is clicked', async () => {
    const prevSpy = jest.fn()
    const nextSpy = jest.fn()
    const {user} = render(
      <ChatPagingComponent currentPage={2} totalPages={4} onPrev={prevSpy} onNext={nextSpy} isUserMessage />,
    )

    const button = await screen.findByRole('button', {name: 'Previous Response'})
    await user.click(button)

    expect(prevSpy).toHaveBeenCalledTimes(1)
    expect(prevSpy).toHaveBeenCalledWith(1)
    expect(nextSpy).not.toHaveBeenCalled()
  })

  it('is not called when previous arrow is disabled', async () => {
    const prevSpy = jest.fn()
    const nextSpy = jest.fn()
    const {user} = render(
      <ChatPagingComponent currentPage={1} totalPages={4} onPrev={prevSpy} onNext={nextSpy} isUserMessage />,
    )

    const button = await screen.findByRole('button', {name: 'Previous Response'})
    await user.click(button)

    expect(prevSpy).not.toHaveBeenCalled()
    expect(nextSpy).not.toHaveBeenCalled()
  })
})

describe('onNext', () => {
  it('is called when next arrow is clicked', async () => {
    const prevSpy = jest.fn()
    const nextSpy = jest.fn()
    const {user} = render(
      <ChatPagingComponent currentPage={2} totalPages={4} onPrev={prevSpy} onNext={nextSpy} isUserMessage />,
    )

    const button = await screen.findByRole('button', {name: 'Next Response'})
    await user.click(button)

    expect(nextSpy).toHaveBeenCalledTimes(1)
    expect(nextSpy).toHaveBeenCalledWith(3)
    expect(prevSpy).not.toHaveBeenCalled()
  })

  it('is not called when next arrow is disabled', async () => {
    const prevSpy = jest.fn()
    const nextSpy = jest.fn()
    const {user} = render(
      <ChatPagingComponent currentPage={4} totalPages={4} onPrev={prevSpy} onNext={nextSpy} isUserMessage />,
    )

    const button = await screen.findByRole('button', {name: 'Next Response'})
    await user.click(button)

    expect(nextSpy).not.toHaveBeenCalled()
    expect(prevSpy).not.toHaveBeenCalled()
  })
})

describe('isDisabled', () => {
  it('disables paging buttons when true', async () => {
    const prevSpy = jest.fn()
    const nextSpy = jest.fn()
    const {user} = render(
      <ChatPagingComponent currentPage={2} totalPages={4} onPrev={prevSpy} onNext={nextSpy} isUserMessage disabled />,
    )

    const nextButton = await screen.findByRole('button', {name: 'Next Response'})
    const prevButton = await screen.findByRole('button', {name: 'Previous Response'})

    expect(prevButton).toBeDisabled()
    expect(nextButton).toBeDisabled()

    await user.click(nextButton)
    await user.click(prevButton)

    expect(nextSpy).not.toHaveBeenCalled()
    expect(prevSpy).not.toHaveBeenCalled()
  })

  it('does not disable paging buttons when false', async () => {
    const prevSpy = jest.fn()
    const nextSpy = jest.fn()
    const {user} = render(
      <ChatPagingComponent
        currentPage={2}
        totalPages={4}
        onPrev={prevSpy}
        onNext={nextSpy}
        isUserMessage
        disabled={false}
      />,
    )

    const nextButton = await screen.findByRole('button', {name: 'Next Response'})
    const prevButton = await screen.findByRole('button', {name: 'Previous Response'})

    expect(prevButton).toBeEnabled()
    expect(nextButton).toBeEnabled()

    await user.click(nextButton)
    await user.click(prevButton)

    expect(nextSpy).toHaveBeenCalled()
    expect(prevSpy).toHaveBeenCalled()
  })
})

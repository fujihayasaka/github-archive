import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {screen, fireEvent, act} from '@testing-library/react'
import {LabelColorPicker, randomHexColor, isValidColor} from '../components/LabelColorPicker'

const userEvent = setupUserEvent()

// Mock the useLabelStyles hook
jest.mock('@github-ui/use-label-styles', () => ({
  useLabelStyles: jest.fn(() => ({color: '#ffffff'})),
}))

describe('LabelColorPicker', () => {
  const initialColor = '#b60205'

  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('renders with initial color', () => {
    render(<LabelColorPicker color={initialColor} />)

    const input = screen.getByRole('textbox')
    expect(input).toHaveValue(initialColor)

    const randomColorButton = screen.getByTitle('Choose random color')
    expect(randomColorButton).toBeInTheDocument()
  })

  it('updates color when text input changes to a valid color', async () => {
    render(<LabelColorPicker color={initialColor} />)

    const input = screen.getByRole('textbox')

    // Change to a valid color
    const newValidColor = '#0e8a16'
    await userEvent.clear(input)
    await userEvent.type(input, newValidColor)

    expect(input).toHaveValue(newValidColor)
  })

  it('only updates input value but not color state when text input changes to an invalid color', async () => {
    render(<LabelColorPicker color={initialColor} />)

    const input = screen.getByRole('textbox')

    // Change to an invalid color
    const invalidColor = 'not-a-color'
    await userEvent.clear(input)
    await userEvent.type(input, invalidColor)

    // Input should show the invalid value
    expect(input).toHaveValue(invalidColor)

    // But input should have error status
    // eslint-disable-next-line testing-library/no-node-access
    expect(input.parentElement).toHaveAttribute('data-validation', 'error')
  })

  it('shows color popup when input is focused', () => {
    render(<LabelColorPicker color={initialColor} />)

    const input = screen.getByRole('textbox')

    // Popup should not be visible initially
    expect(screen.queryByText('Choose from default colors')).not.toBeInTheDocument()

    // Focus the input
    fireEvent.focus(input)

    // Popup should now be visible
    expect(screen.getByText('Choose from default colors')).toBeInTheDocument()
  })

  it('changes color when a preset color is selected', async () => {
    render(<LabelColorPicker color={initialColor} />)

    const input: HTMLInputElement = screen.getByRole('textbox')

    // Focus to show popup
    fireEvent.focus(input)

    // Find and click on a color from the preset
    const firstDarkColor = screen.getByLabelText('#f9d0c4')
    await userEvent.click(firstDarkColor)

    // Input value should change
    expect(input.value).toBe('#f9d0c4')
  })

  it('supports keyboard tab navigation through color options', async () => {
    render(<LabelColorPicker color={'#f00'} />)

    const input: HTMLInputElement = screen.getByRole('textbox')

    // Focus the input to show popup
    act(() => input.focus())

    // Verify popup is open
    expect(screen.getByText('Choose from default colors')).toBeInTheDocument()

    // Tab to navigate to the first color option
    await userEvent.tab()

    // First color option should be focused
    const firstDarkColorOption = screen.getByLabelText('#b60205')
    expect(firstDarkColorOption).toHaveFocus()

    // Press Enter to select the first color
    await userEvent.keyboard('{Enter}')
    expect(input.value).toBe('#b60205')

    // Focus the input again to reopen the popup
    act(() => input.focus())

    // Tab to the first color option and then to the second
    await userEvent.tab()
    await userEvent.tab()

    // Second color option should be focused
    const secondDarkColorOption = screen.getByLabelText('#d93f0b')
    expect(secondDarkColorOption).toHaveFocus()

    // Press the spacebar to select the second color
    await userEvent.keyboard(' ')
    expect(input.value).toBe('#d93f0b')
  })

  it('generates random color when random button is clicked', async () => {
    render(<LabelColorPicker color={initialColor} />)

    const input: HTMLInputElement = screen.getByRole('textbox')
    const randomColorButton = screen.getByTitle('Choose random color')

    // Initial value
    expect(input).toHaveValue(initialColor)

    // Click random color button
    await userEvent.click(randomColorButton)

    // Input value should change to a different color
    expect(input.value).not.toBe(initialColor)
    expect(input.value).toMatch(/^#[0-9A-Fa-f]{6}$/)
  })
})

// Test the utility functions separately
describe('Color utility functions', () => {
  describe('randomHexColor', () => {
    it('generates a valid hex color', () => {
      const color = randomHexColor()
      expect(color).toMatch(/^#[0-9A-Fa-f]{6}$/)
    })

    it('generates different colors on multiple calls', () => {
      const color1 = randomHexColor()
      const color2 = randomHexColor()
      const color3 = randomHexColor()

      // There's a tiny possibility this could fail randomly
      // if the same color is generated twice
      const uniqueColors = new Set([color1, color2, color3])
      expect(uniqueColors.size).toBeGreaterThan(1)
    })
  })

  describe('isValidColor', () => {
    it('returns true for valid 6-digit hex colors', () => {
      expect(isValidColor('#123456')).toBe(true)
      expect(isValidColor('#abcdef')).toBe(true)
      expect(isValidColor('#ABCDEF')).toBe(true)
    })

    it('returns true for valid 3-digit hex colors', () => {
      expect(isValidColor('#123')).toBe(true)
      expect(isValidColor('#abc')).toBe(true)
      expect(isValidColor('#ABC')).toBe(true)
    })

    it('returns false for invalid colors', () => {
      expect(isValidColor('123456')).toBe(false) // Missing #
      expect(isValidColor('#12345')).toBe(false) // 5 digits
      expect(isValidColor('#1234567')).toBe(false) // 7 digits
      expect(isValidColor('#gggggg')).toBe(false) // Invalid hex
      expect(isValidColor('red')).toBe(false) // Color name
    })
  })
})

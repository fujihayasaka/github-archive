import type {Meta, StoryObj} from '@storybook/react'
import {expect, userEvent, waitFor, within} from '@storybook/test'

import {moveCursor} from '../__tests__/utils/interaction-test-helpers'
import {setupMockFilterProviders} from '../__tests__/utils/mock-providers'
import {Filter, type FilterProps} from '../Filter'
import {handlers} from '../mocks/handlers'
import styles from './filterRules.module.css'

const meta = {
  title: 'Recipes/Filter/Rules',
  component: Filter,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    msw: {
      handlers,
    },
  },
  tags: ['flaky'],
  argTypes: {
    onChange: {action: 'onChange'},
    onParse: {action: 'onParse'},
    onSubmit: {action: 'onSubmit'},
    onValidation: {action: 'onValidation'},
  },
  args: {
    id: 'storybook-filter',
    providers: setupMockFilterProviders(),
    settings: {aliasMatching: false, groupAndKeywordSupport: true},
    label: 'Filter items',
    context: {repo: 'github/github'},
  },
} satisfies Meta<typeof Filter>

export default meta

type RuleProps = FilterProps & {title?: string; description?: string}
type Story = StoryObj<RuleProps>

type RuleBlockProps = {title?: string; description?: string}

const RuleBlock = ({title, description}: RuleBlockProps) => {
  if (!title && !description) return null
  return (
    <div className={styles.ruleBlock}>
      {title && <h1 className={styles.ruleBlockTitle}>{title}</h1>}
      {description && <h2 className={styles.ruleBlockDescription}>{description}</h2>}
    </div>
  )
}

const defaultStory: Story = {
  name: 'Default',
  render: (storyProps: RuleProps) => {
    const {title, description, ...props} = storyProps
    return (
      <>
        <RuleBlock title={title} description={description} />
        <Filter {...props} />
      </>
    )
  },
}

export const onInputFocusWithNoValue: Story = {
  ...defaultStory,
  args: {
    ...meta.args,
    title: 'Show suggestions when input has no value',
    description: 'Should show suggestions when a user focuses on the filter input and it has no value',
  },
  name: 'Show suggestions when input has no value',
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole('combobox')

    await expect(input).toHaveAttribute('aria-expanded', 'false')
    await userEvent.click(input)
    await expect(input).toHaveFocus()
    await expect(input).toHaveAttribute('aria-expanded', 'true')
    await waitFor(() => expect(canvas.getByRole('listbox', {name: 'Suggestions'})).toBeInTheDocument())
  },
}

export const onInputFocusWithValue: Story = {
  ...defaultStory,
  args: {
    ...meta.args,
    title: "Don't show suggestions when input has a value",
    description: "Shouldn't show suggestions when a user focuses on the filter input and it has a value",
    initialFilterValue: 'state:open',
  },
  name: "Don't show suggestions when input has a value",
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole<HTMLInputElement>('combobox')

    await expect(input).toHaveAttribute('aria-expanded', 'false')
    await userEvent.click(input)
    input.selectionStart = 10
    await expect(input).toHaveFocus()
    await expect(input).toHaveAttribute('aria-expanded', 'false')
    await waitFor(() => expect(canvas.queryByRole('listbox', {name: 'Suggestions'})).not.toBeInTheDocument())
  },
}

export const showSuggestionsWhenSpacePressed: Story = {
  ...defaultStory,
  args: {
    ...meta.args,
    title: 'Show suggestions when a space is added',
    description: "Should show suggestions when a user adds a space character to the filter's value",
  },
  name: 'Show suggestions when a space is added',
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    const input = canvas.getByRole('combobox')

    await expect(input).toHaveAttribute('aria-expanded', 'false')
    await userEvent.type(input, 's')
    await userEvent.keyboard('{ArrowDown}')
    await userEvent.keyboard('{Enter}')
    await expect(input).toHaveValue('state:')

    await userEvent.keyboard('{ArrowDown}')
    await userEvent.keyboard('{Enter}')
    await expect(input).toHaveValue('state:open')

    await userEvent.keyboard(' ')
    await expect(input).toHaveAttribute('aria-expanded', 'true')
    await waitFor(() => expect(canvas.getByRole('listbox', {name: 'Suggestions'})).toBeInTheDocument())
    await userEvent.keyboard('{Backspace}')
    await expect(input).toHaveAttribute('aria-expanded', 'false')
  },
}

export const showSuggestionsWhenInsideGroupBlock: Story = {
  ...defaultStory,
  args: {
    ...meta.args,
    title: 'Show suggestions when inside a group block',
    description:
      'When the caret is to the right of a (, the suggestions menu should appear, and selecting an item replaces the filter block',
    initialFilterValue: 'state:open AND (is:issue OR is:pr)',
  },
  name: 'Show suggestions when inside a group block',
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole<HTMLInputElement>('combobox')
    await expect(input).toHaveAttribute('aria-expanded', 'false')

    await userEvent.click(input)
    input.selectionStart = 16
    await userEvent.keyboard('t')
    await expect(input).toHaveAttribute('aria-expanded', 'true')
    await expect(canvas.getByRole('listbox', {name: 'Suggestions'})).toBeInTheDocument()

    await userEvent.keyboard('{ArrowDown}')
    await userEvent.keyboard('{Enter}')
    await expect(input).toHaveValue('state:open AND (type:issue OR is:pr)')
  },
}

export const showSuggestionMenuWhenInsideSpaceBlocks: Story = {
  ...defaultStory,
  args: {
    ...meta.args,
    title: 'Show suggestions menu when inside space blocks',
    description:
      'When there are multiple spaces, and the cursor is in the middle, then a user types, the suggestions menu appears',
    initialFilterValue: 'state:open AND  (is:issue OR is:pr)',
  },
  name: 'Show suggestion menu when inside space blocks',
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole<HTMLInputElement>('combobox')
    await expect(input).toHaveAttribute('aria-expanded', 'false')

    await userEvent.click(input)
    input.selectionStart = 15
    await userEvent.keyboard('t')
    await expect(input).toHaveAttribute('aria-expanded', 'true')
    await expect(canvas.getByRole('listbox', {name: 'Suggestions'})).toBeInTheDocument()

    await userEvent.keyboard('{ArrowDown}')
    await userEvent.keyboard('{Enter}')
    await expect(input).toHaveValue('state:open AND type: (is:issue OR is:pr)')
  },
}

export const DontShowSuggestionsWhenParenthesisIsInsideQuotes: Story = {
  ...defaultStory,
  args: {
    ...meta.args,
    title: "Don't show suggestions when parenthesis is inside quotes",
    initialFilterValue: 'state:"open',
  },
  name: "Don't show suggestions when parenthesis is inside quotes",
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole<HTMLInputElement>('combobox')
    await userEvent.click(input)

    moveCursor(canvas, 'state:"open'.length)
    await userEvent.keyboard('(')
    await expect(input).toHaveAttribute('aria-expanded', 'false')
    await userEvent.keyboard('{Backspace}')

    await userEvent.keyboard('","bloop (')
    await expect(input).toHaveAttribute('aria-expanded', 'false')
  },
}

export const ShowSuggestionsWhenParenthesisIsAfterSpace: Story = {
  ...defaultStory,
  args: {
    ...meta.args,
    title: 'Show suggestions when parenthesis is after space',
    initialFilterValue: 'state:open',
  },
  name: 'Show suggestions when parenthesis is after space',
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole<HTMLInputElement>('combobox')
    await userEvent.click(input)

    moveCursor(canvas, 'state:open'.length)
    await userEvent.keyboard(' (')
    await expect(input).toHaveAttribute('aria-expanded', 'true')
    await userEvent.keyboard('(')
    await expect(input).toHaveAttribute('aria-expanded', 'true')
  },
}

export const ShowSuggestionsWhenMultipleParentheses: Story = {
  ...defaultStory,
  args: {
    ...meta.args,
    title: 'Show suggestions when there are multiple parentheses',
  },
  name: 'Show suggestions when there are multiple parentheses',
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole<HTMLInputElement>('combobox')
    await userEvent.click(input)

    await userEvent.keyboard('(')
    await expect(input).toHaveAttribute('aria-expanded', 'true')
    await userEvent.keyboard('(')
    await expect(input).toHaveAttribute('aria-expanded', 'true')
  },
}

export const DontValidateUnmatchedClosingParenAsValue: Story = {
  ...defaultStory,
  args: {
    ...meta.args,
    title: "Don't validate unmatched closing paren as value",
    description:
      "When a closing paren is typed immediately after a filter value, we don't want to treat it as part of the value. The value should be highlighted when valid, but the closing paren should not be highlighted and instead styled like the default text.",
  },
  name: "Don't validate unmatched closing paren as value",
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole('combobox')
    const styledInput = canvas.getByTestId('styled-input-content')

    await userEvent.type(input, 'state:open) ')
    await expect(styledInput.querySelector('[data-type="filter-value"]')?.textContent).toEqual('open')
    await expect(canvas.queryByTestId('filter-sb-validation-message')).not.toBeInTheDocument()
    await expect(canvas.queryByTestId('validation-error-list')).not.toBeInTheDocument()
  },
}

export const ValidatesFilterValueWithClosingParenAsText: Story = {
  ...defaultStory,
  args: {
    ...meta.args,
    title: 'Validates filter value with closing paren and additional text',
    description:
      'When a closing paren is typed as part of a filter value and then there is additional text after that, the value is before the closing paren, the closing paren is unbalanced, and the rest is text.',
  },
  name: 'Validates filter value with closing paren and additional text',
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole('combobox')

    await userEvent.type(input, 'state:open)foo ')
    await userEvent.keyboard('{Enter}')
    await expect(canvas.getByTestId('validation-error-list')).toHaveTextContent('Unbalanced parentheses')
  },
}

export const ValidatesFilterValueAsPartOfValueWhenInQuotes: Story = {
  ...defaultStory,
  args: {
    ...meta.args,
    title: 'Validates filter value when close paren is part of a quoted value',
    description:
      'When a closing paren is typed as part of a filter value that is quoted, the quoted value will be validated',
  },
  name: 'Validates filter value when close paren is part of a quoted value',
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole('combobox')
    const styledInput = canvas.getByTestId('styled-input-content')

    await userEvent.type(input, 'state:"open)')
    await userEvent.keyboard('{Tab}')
    await expect(styledInput.querySelector('[data-type="filter-value"]')?.textContent).toEqual('"open)"')
    await expect(canvas.getByTestId('validation-error-list')).toHaveTextContent('Invalid value "open)" for state')
    await userEvent.click(input)
    moveCursor(canvas, 'state:"open)'.length)
    await userEvent.keyboard('{Backspace}')
  },
}

export const WrapsValuesWithUnmatchedParensInQuotes: Story = {
  ...defaultStory,
  args: {
    ...meta.args,
    title: 'Should wrap values with an unmatched parenthesis in quotes when suggestion selected',
    description:
      'When a value contains an unmatched parenthesis, it should be wrapped in quotes to avoid it being treated as the start/end of a group after it is selected from the suggestions list',
  },
  name: 'Should wrap values with unmatched parentheses in quotes',
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole('combobox')

    await userEvent.type(input, '(label:cool')
    await userEvent.keyboard('{Delete}')
    await waitFor(() => {
      canvas.getByRole('option', {name: '(cool, Label'}).click()
    })

    await expect(input).toHaveValue('(label:"(cool"')
  },
}

export const WrapsValuesWithParensInQuotes: Story = {
  ...defaultStory,
  args: {
    ...meta.args,
    title: 'Should wrap values with parenthesis in quotes when suggestion selected',
    description:
      'When a value contains parenthesis, it should be wrapped in quotes to avoid it being treated as the start/end of a group after it is selected from the suggestions list',
  },
  name: 'Should wrap values with parentheses in quotes',
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole('combobox')

    await userEvent.type(input, 'label:a11')
    await waitFor(() => {
      canvas.getByRole('option', {name: 'a11y (sev 1), Label'}).click()
    })

    await expect(input).toHaveValue('label:"a11y (sev 1)"')
  },
}

export const AutoClosingParentheses: Story = {
  ...defaultStory,
  args: {
    ...meta.args,
    title: 'Auto add closing parentheses',
    description: 'Automatically add closing parenthesis when the opening parenthesis is added',
    initialFilterValue: 'state:open  status:success',
  },
  name: 'Auto add closing parentheses',
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole('combobox')

    await userEvent.click(input)
    moveCursor(canvas, 'state:open '.length)
    await userEvent.keyboard('(')
    await expect(input).toHaveValue('state:open () status:success')
    await userEvent.keyboard('a')
    await expect(input).toHaveValue('state:open (a) status:success')

    await userEvent.type(input, ' {{')
    await expect(input).toHaveValue('state:open (a) status:success {') // does not auto close curly brackets
  },
}

export const AutoClosingQuotes: Story = {
  ...defaultStory,
  args: {
    ...meta.args,
    title: 'Auto add closing quotes',
    description: 'Automatically add closing quote when the opening quote is added',
    initialFilterValue: 'state:open  status:success',
  },
  name: 'Auto add closing quotes',
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole('combobox')

    await userEvent.click(input)
    moveCursor(canvas, 'state:open '.length)
    await userEvent.keyboard('"')
    await expect(input).toHaveValue('state:open "" status:success')
    await userEvent.keyboard('a')
    await expect(input).toHaveValue('state:open "a" status:success')
  },
}

export const AutoClosingDelete: Story = {
  ...defaultStory,
  args: {
    ...meta.args,
    title: 'Auto delete closing parentheses and quotes',
    description:
      'Automatically delete closing parentheses or quotes when the opening parenthesis or quote is deleted, respectively',
    initialFilterValue: 'state:open () status:success',
  },
  name: 'Auto delete closing parentheses and quotes',
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole('combobox')

    await userEvent.click(input)
    moveCursor(canvas, 'state:open ('.length)
    await userEvent.keyboard('{Backspace}')
    await expect(input).toHaveValue('state:open  status:success')

    await userEvent.keyboard('"')
    await expect(input).toHaveValue('state:open "" status:success')
    await userEvent.keyboard('{Backspace}')
    await expect(input).toHaveValue('state:open  status:success')
  },
}

export const DontAutoCloseParenthesesInsideQuotes: Story = {
  ...defaultStory,
  args: {
    ...meta.args,
    title: "Don't auto close parentheses when inside quotes",
    description:
      'When a value is wrapped in quotes, the parentheses do not auto close to avoid invalid filter values such as those with emojis i.e. :(',
  },
  name: "Don't auto close parentheses when inside quotes",
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole('combobox')

    await userEvent.type(input, 'state:"open')
    await expect(input).toHaveValue('state:"open"')
    moveCursor(canvas, 'state:"open'.length)
    await userEvent.keyboard(' (')
    await expect(input).toHaveValue('state:"open ("')
  },
}

export const DontAutoCloseParenthesesBeforeCharacter: Story = {
  ...defaultStory,
  args: {
    ...meta.args,
    title: "Don't auto close parentheses before a character",
    description:
      'The parentheses do not auto close before a closing character or a word character to wrap existing filter',
    initialFilterValue: 'state:open status:success',
  },
  name: "Don't auto close parentheses before a character",
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole('combobox')

    await userEvent.click(input)
    moveCursor(canvas, 'state:open '.length)
    await userEvent.keyboard('(')
    await expect(input).toHaveValue('state:open (status:success')
    moveCursor(canvas, 'state:open (status:success'.length)
    await userEvent.keyboard(')')
    await expect(input).toHaveValue('state:open (status:success)')
    moveCursor(canvas, 'state:open (status:success'.length)
    await userEvent.keyboard('(')
    await expect(input).toHaveValue('state:open (status:success()')
    await userEvent.keyboard('{Backspace})')
    await expect(input).toHaveValue('state:open (status:success)')
  },
}

// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {within} from '@storybook/test'

export const getSuggestions = (canvas: ReturnType<typeof within>) => {
  return within(canvas.getByTestId('filter-results'))
    .getAllByRole('option')
    .map(suggestion => suggestion.textContent)
}

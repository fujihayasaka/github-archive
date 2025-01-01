import {setupUserEvent} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {expectFilterValueToBe} from '../__tests__/utils/helpers'

const userEvent = setupUserEvent()

export const setupExpectedAsyncErrorHandler = () => {
  jest.spyOn(console, 'error').mockImplementation((message: string) => {
    // * Because Filter is asynchronous, there are console errors that are thrown, but expected. This will rethrow
    // * any errors that are not related to the async nature of the component.
    if (!message.includes?.('wrapped in act(')) {
      // eslint-disable-next-line no-console
      console.error(message)
    }
  })
}

export async function updateFilterValue(filterValue: string) {
  screen.getByRole('combobox').focus()

  await userEvent.paste(filterValue)

  await expectFilterValueToBe(filterValue)
}

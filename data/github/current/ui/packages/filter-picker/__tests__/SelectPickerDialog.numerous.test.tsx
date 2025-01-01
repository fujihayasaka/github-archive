import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {SelectPickerDialog} from '../SelectPickerDialog'
import {fruitItemConfig, numerousFruits} from '../test-utils/mock-data'

// Mocking the concatAndDedup function to skip rendering items, so 2.3k test is faster
jest.mock('../helper/concat-and-dedup', () => ({
  concatAndDedup: () => [],
}))

describe('SelectPickerDialog numerous', () => {
  it('uses human number formatting', async () => {
    render(
      <SelectPickerDialog
        providers={[]}
        selected={numerousFruits}
        title="Select"
        onDismiss={jest.fn()}
        onSubmit={jest.fn()}
        itemConfig={fruitItemConfig}
        selectionVariant="multiple"
      />,
    )

    expect(await screen.findByRole('button', {name: 'Select (2.3k)'})).toBeInTheDocument()
  })
})

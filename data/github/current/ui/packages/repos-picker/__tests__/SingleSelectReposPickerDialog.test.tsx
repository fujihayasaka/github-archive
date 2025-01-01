import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {SingleSelectReposPickerDialog} from '../SingleSelectReposPickerDialog'

type DialogProps = React.ComponentProps<typeof SingleSelectReposPickerDialog>
const defaultProps: DialogProps = {
  scope: {type: 'organization', slug: 'acme'},
  onSubmit: jest.fn(),
  onDismiss: jest.fn(),
}

describe('SingleSelectReposPickerDialog', () => {
  it('Submits on cmd + Enter', async () => {
    const onSubmitMock = jest.fn()
    const {user} = renderDialog({onSubmit: onSubmitMock})

    const searchBar = screen.getByRole('combobox')
    await user.click(searchBar)

    await user.keyboard('{Control>}{Enter}')

    expect(onSubmitMock).toHaveBeenCalled()
  })
})

function renderDialog(props: Partial<DialogProps> = {}) {
  return render(<SingleSelectReposPickerDialog {...defaultProps} {...props} />)
}

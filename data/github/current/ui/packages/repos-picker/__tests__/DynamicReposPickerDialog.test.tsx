import {render} from '@github-ui/react-core/test-utils'
import {getRepoFilterProviders} from '@github-ui/repos-filter/providers'
import {screen, within} from '@testing-library/react'

import {DynamicReposPickerDialog} from '../DynamicReposPickerDialog'

type DialogProps = React.ComponentProps<typeof DynamicReposPickerDialog>
const defaultProps: DialogProps = {
  scope: {type: 'organization', slug: 'acme'},
  onSubmit: jest.fn(),
  onDismiss: jest.fn(),
  providers: [],
}

describe('DynamicReposPickerDialog', () => {
  it('Shows validation message for unsupported providers in alphabetic order', async () => {
    const {user} = renderDialog({providers: getRepoFilterProviders(['fork']), warnIfUnsupportedProvider: true})

    await user.click(screen.getByRole('combobox'))
    await user.paste('fork:true visibility:public availability:1 free text')
    await user.type(screen.getByRole('combobox'), '{Enter}')

    const errorList = screen.getByTestId('validation-error-list')

    expect(within(errorList).getAllByRole('listitem')).toHaveLength(3)

    const [freeTextError, availabilityError, visibilityError] = within(errorList).getAllByRole('listitem')

    expect(freeTextError).toHaveTextContent('Free text is not supported.')
    expect(availabilityError).toHaveTextContent('availability is not supported.')
    expect(visibilityError).toHaveTextContent('visibility is not supported.')
  })

  it('Shows no validation messages when `warnIfUnsupportedProvider` is disabled', async () => {
    const {user} = renderDialog({providers: getRepoFilterProviders(['fork']), warnIfUnsupportedProvider: false})

    await user.click(screen.getByRole('combobox'))
    await user.paste('fork:true visibility:public availability:1 free text')
    await user.type(screen.getByRole('combobox'), '{Enter}')

    expect(screen.queryByTestId('validation-error-list')).not.toBeInTheDocument()
  })

  it('Submits on cmd + Enter', async () => {
    const onSubmitMock = jest.fn()
    const {user} = renderDialog({onSubmit: onSubmitMock})

    await user.click(screen.getByRole('combobox'))
    await user.paste('text')
    await user.keyboard('{Control>}{Enter}')

    expect(onSubmitMock).toHaveBeenCalledWith('text')
  })
})

function renderDialog(props: Partial<DialogProps> = {}) {
  return render(<DynamicReposPickerDialog {...defaultProps} {...props} />)
}

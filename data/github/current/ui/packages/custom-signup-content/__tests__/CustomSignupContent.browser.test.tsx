import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {expect, it} from '@github-ui/tests'
import {CustomSignupContent} from '../CustomSignupContent'
import {getCustomSignupContentProps, getCustomSignupContentPropsNoContentEntries} from './utils/mock-data'

it('Renders the CustomSignupContent', () => {
  const props = getCustomSignupContentProps()
  render(<CustomSignupContent {...props} />)

  const heading = screen.getByRole('heading', {level: 2, name: props.contentfulContent.entry.fields.heading})
  const label = screen.getByTestId('Label')

  expect(heading).toBeInTheDocument()
  expect(label).toHaveTextContent('Optional')
})

it('Does not show the label pill if not included in Contentful payload', () => {
  const props = getCustomSignupContentPropsNoContentEntries()
  render(<CustomSignupContent {...props} />)

  const heading = screen.getByRole('heading', {level: 2, name: props.contentfulContent.entry.fields.heading})
  const label = screen.queryByTestId('Label')

  expect(heading).toBeInTheDocument()
  expect(label).not.toBeInTheDocument()
})

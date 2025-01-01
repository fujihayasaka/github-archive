import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {expect, it} from '@github-ui/tests'
import {IntegrationPermissionSelector} from '../IntegrationPermissionSelector'
import {getIntegrationPermissionSelectorProps} from './utils/mock-data'

it('Renders the IntegrationPermissionSelector', () => {
  const props = getIntegrationPermissionSelectorProps()
  render(<IntegrationPermissionSelector {...props} />)
  expect(screen.getByRole('article')).toHaveTextContent(props.exampleMessage)
})

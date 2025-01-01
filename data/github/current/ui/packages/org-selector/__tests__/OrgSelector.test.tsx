import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {OrgSelector} from '../OrgSelector'

test('Renders the OrgSelector', () => {
  const message = 'Select organizations'
  render(
    <OrgSelector
      selection={[]}
      selectionVariant="multiple"
      selectOrg={() => {}}
      removeOrg={() => {}}
      orgLoader={async () => {
        return []
      }}
    />,
  )
  expect(screen.getByRole('button')).toHaveTextContent(message)
})

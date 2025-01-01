import {TransparencyDataTable} from '../../../apps/transparency/TransparencyDataTable'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

describe('TransparencyDataTable', () => {
  it('Renders items that have a value', () => {
    render(
      <TransparencyDataTable
        items={[
          {
            label: 'label1',
            value: 'value1',
          },
          {
            label: 'label2',
            value: 'value2',
          },
          {
            label: 'label3',
            value: undefined,
          },
        ]}
      />,
    )

    expect(screen.getByText('label1')).toBeInTheDocument()
    expect(screen.getByText('value1')).toBeInTheDocument()
    expect(screen.getByText('label2')).toBeInTheDocument()
    expect(screen.getByText('value2')).toBeInTheDocument()
    expect(screen.queryByText('label3')).not.toBeInTheDocument()
  })
})

import {render} from '@github-ui/react-core/test-utils'

import {TokenizedQuery} from '../TokenizedQuery'

describe('TokenizedQuery', () => {
  it('correctly renders negation', async () => {
    render(<TokenizedQuery query="-fork:true -props.env:true" />)

    expect(document.body).toHaveTextContent('-fork:true-props.env:true')
  })
})

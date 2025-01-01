import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import TalkToUs from '../components/TalkToUs'
import {swallowCSSParsingError} from '../test-utils/test-helper'

describe('TalkToUs', () => {
  beforeEach(swallowCSSParsingError)

  test('renders', () => {
    render(<TalkToUs onDismiss={() => {}} />)
    expect(
      screen.getByText('We want to make this settings experience amazing for you!', {exact: false}),
    ).toBeInTheDocument()
  })
})

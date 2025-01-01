import {render, screen} from '@testing-library/react'

import {getRepositoryMock} from '../../../test-utils/mock-data'
import {ContextLabel} from '../ContextLabel'

describe('ContextLabel', () => {
  describe('with no context', () => {
    it('should render nothing', () => {
      const {container} = render(<ContextLabel />)
      expect(container).toBeEmptyDOMElement()
    })
  })

  describe('with repository context', () => {
    it('should render nothing', () => {
      const {container} = render(
        <ContextLabel
          context={{
            type: 'repository',
            ...getRepositoryMock(),
          }}
        />,
      )
      expect(container).toBeEmptyDOMElement()
    })
  })

  describe('with pull request context', () => {
    it('should render label', () => {
      render(
        <ContextLabel
          context={{
            type: 'pull-request',
            number: 123,
            persona: 'reviewer',
          }}
        />,
      )

      expect(screen.getByText('123')).toBeInTheDocument()
    })
  })
})

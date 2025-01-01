import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {Main} from '../routes/Main'
import {getMainRoutePayload} from '../test-utils/mock-data'
import {Constants, CuratedImagePointersTableConstants, CuratedImagesTableConstants} from '../helpers/constants'

test('Renders Main', () => {
  const routePayload = getMainRoutePayload()
  routePayload.imageDefinitions = []
  render(<Main />, {
    routePayload,
  })
  expect(screen.getByText(Constants.stafftoolPageTitle)).toBeInTheDocument()
  expect(screen.getByText(CuratedImagePointersTableConstants.blankStateTitle)).toBeInTheDocument()
  expect(screen.getByText(CuratedImagesTableConstants.blankStateTitle)).toBeInTheDocument()
})

test('Renders Main With Image Table and Pointer Table', () => {
  const routePayload = getMainRoutePayload()
  render(<Main />, {
    routePayload,
  })
  expect(screen.getByText(Constants.stafftoolPageTitle)).toBeInTheDocument()
  expect(screen.getByText('test-name-1')).toBeInTheDocument()
})

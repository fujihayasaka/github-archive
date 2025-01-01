import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {CopilotDetails} from '../CopilotDetails'
import {getCopilotDetailsProps} from '../test-utils/mock-data'

describe('CopilotDetails Component', () => {
  test('Renders the CopilotDetails component', () => {
    const props = getCopilotDetailsProps()
    render(<CopilotDetails {...props} />)
    expect(screen.getByTestId('licensing-copilot-details')).toBeInTheDocument()
  })

  test('Renders the CopilotLicensingHeader component', () => {
    const props = getCopilotDetailsProps()
    render(<CopilotDetails {...props} />)
    expect(screen.getByLabelText('Breadcrumbs')).toBeInTheDocument()
    expect(screen.getByTestId('licensing-copilot-header')).toBeInTheDocument()
    expect(screen.getByTestId('download-csv-button')).toBeInTheDocument()
  })

  test('Renders the CopilotOrgGeneralAccess component', () => {
    const props = getCopilotDetailsProps()
    render(<CopilotDetails {...props} />)
    expect(screen.getByTestId('licensing-copilot-access-org-enablement')).toBeInTheDocument()
    expect(
      screen.getByText(
        /Control which organizations will have access to Copilot Business and Copilot Enterprise inside your enterprise/i,
      ),
    ).toBeInTheDocument()
  })

  test('Renders the CopilotAccessList component', () => {
    const props = getCopilotDetailsProps()
    render(<CopilotDetails {...props} />)
    expect(screen.getByTestId('licensing-copilot-access-list')).toBeInTheDocument()
  })

  test('Renders the CopilotOrganizationAccessList component by default', () => {
    const props = getCopilotDetailsProps()
    render(<CopilotDetails {...props} />)
    expect(screen.getByTestId('licensing-copilot-organization-access-list-view')).toBeInTheDocument()
  })

  test('Renders the CopilotDangerZone component', () => {
    const props = getCopilotDetailsProps()
    render(<CopilotDetails {...props} />)
    expect(screen.getByTestId('licensing-copilot-danger-zone')).toBeInTheDocument()
    expect(
      screen.getByText('Remove Copilot access for all members and organizations in the entire enterprise'),
    ).toBeInTheDocument()
  })
})

import {SecurityAndComplianceInfo} from '../../../apps/transparency/SecurityAndComplianceInfo'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

describe('SecurityAndComplianceInfo', () => {
  describe('indemnity status', () => {
    it('renders label and value when copilotApp is true', () => {
      render(<SecurityAndComplianceInfo copilotApp />)

      expect(screen.getByText('Indemnity Status')).toBeInTheDocument()
      expect(
        screen.getByText(
          "Not covered by Microsoft's indemnity policy. All other Copilot features retain indemnity coverage.",
        ),
      ).toBeInTheDocument()
    })

    it('does not render when copilotApp is false', () => {
      render(<SecurityAndComplianceInfo copilotApp={false} />)

      expect(screen.queryByText('Indemnity Status')).not.toBeInTheDocument()
    })
  })

  describe('ai risk level', () => {
    it('renders label and text when isAiHighRisk is present', () => {
      render(<SecurityAndComplianceInfo isAiHighRisk="Yes" copilotApp={false} />)

      expect(screen.getByText('Classified as high risk by EU AI Act')).toBeInTheDocument()
      expect(screen.getByText('Yes')).toBeInTheDocument()
    })

    it('does not render when isAiHighRisk is not present', () => {
      render(<SecurityAndComplianceInfo isAiHighRisk={undefined} copilotApp={false} />)

      expect(screen.queryByText('Classified as high risk by EU AI Act')).not.toBeInTheDocument()
    })
  })

  describe('llms in use', () => {
    it('renders label and value when llmsInUse is present', () => {
      render(<SecurityAndComplianceInfo llmsInUse="some llm, some other llm" copilotApp={false} />)

      expect(screen.getByText('Models used')).toBeInTheDocument()
      expect(screen.getByText('some llm, some other llm')).toBeInTheDocument()
    })

    it('does not render when llmsInUse is not present', () => {
      render(<SecurityAndComplianceInfo llmsInUse="" copilotApp={false} />)

      expect(screen.queryByText('Models used')).not.toBeInTheDocument()
    })
  })

  describe('third party services', () => {
    it('renders label and value when thirdPartyServices is present', () => {
      render(<SecurityAndComplianceInfo thirdPartyServices="some service, some other service" copilotApp={false} />)

      expect(screen.getByText('Third party services used')).toBeInTheDocument()
      expect(screen.getByText('some service, some other service')).toBeInTheDocument()
    })

    it('does not render when thirdPartyServices is not present', () => {
      render(<SecurityAndComplianceInfo thirdPartyServices="" copilotApp={false} />)

      expect(screen.queryByText('Third party services used')).not.toBeInTheDocument()
    })
  })

  describe('repository visibility', () => {
    it('renders label and capitalized value when repositoryVisibility is present', () => {
      render(<SecurityAndComplianceInfo repositoryVisibility="public" copilotApp={false} />)

      expect(screen.getByText('Repository visibility')).toBeInTheDocument()
      expect(screen.getByText('Public')).toBeInTheDocument()
    })

    it('does not render when repositoryVisibility is not present', () => {
      render(<SecurityAndComplianceInfo repositoryVisibility={undefined} copilotApp={false} />)

      expect(screen.queryByText('Repository visibility')).not.toBeInTheDocument()
    })
  })

  describe('repository url', () => {
    it('renders label and link when repositoryUrl is present', () => {
      render(<SecurityAndComplianceInfo repositoryUrl="https://example.com" copilotApp={false} />)

      expect(screen.getByText('Repository URL')).toBeInTheDocument()
      expect(screen.getByRole('link', {name: 'https://example.com'})).toHaveAttribute('href', 'https://example.com')
    })

    it('does not render when repositoryUrl is not present', () => {
      render(<SecurityAndComplianceInfo repositoryUrl="" copilotApp={false} />)

      expect(screen.queryByText('Repository URL')).not.toBeInTheDocument()
    })
  })

  describe('disclosures', () => {
    it('renders label and html when transparencyDisclosure is present', () => {
      render(<SecurityAndComplianceInfo transparencyDisclosure="<h1>Some disclosure<h1>" copilotApp={false} />)

      expect(screen.getByText('Disclosures')).toBeInTheDocument()
      expect(screen.getByRole('heading', {name: 'Some disclosure'})).toBeInTheDocument()
    })

    it('does not render when transparencyDisclosure is not present', () => {
      render(<SecurityAndComplianceInfo transparencyDisclosure="" copilotApp={false} />)

      expect(screen.queryByText('Disclosures')).not.toBeInTheDocument()
    })
  })
})

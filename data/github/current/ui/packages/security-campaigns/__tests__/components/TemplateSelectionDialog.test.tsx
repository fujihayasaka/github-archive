import {screen} from '@testing-library/react'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {TemplateSelectionDialog, type TemplateSelectionDialogProps} from '../../components/TemplateSelectionDialog'
import type {SecurityCampaignTemplate} from '../../types/security-campaign-template'

describe('TemplateSelectionDialog', () => {
  const templateWithQuery = {
    id: '1',
    name: 'Template 1',
    description: 'Description 1',
    href: '/template1',
    query: 'is:open',
  }
  const templates: SecurityCampaignTemplate[] = [
    templateWithQuery,
    {id: '2', name: 'Template 2', description: 'Description 2', href: '/template2', query: null},
  ]

  const setIsOpen = jest.fn()

  const defaultProps: TemplateSelectionDialogProps = {
    setIsOpen,
    templates,
    organizationLogin: 'github',
  }

  const render = (props?: Partial<TemplateSelectionDialogProps>) =>
    reactRender(<TemplateSelectionDialog {...defaultProps} {...props} />)

  test('renders dialog with correct title', async () => {
    render()

    const dialogTitle = screen.getByText('Select a template for your campaign')
    expect(dialogTitle).toBeInTheDocument()
  })

  test('displays templates in the dialog', async () => {
    render()

    for (const template of templates) {
      expect(screen.getByText(template.name)).toBeInTheDocument()
      expect(screen.getByText(template.description)).toBeInTheDocument()
    }
  })

  test('constructs correct templates url when query is present', async () => {
    render()

    expect(screen.getByRole('link', {name: templateWithQuery.name})).toHaveAttribute(
      'href',
      `/orgs/github/security/campaigns/new?query=is%3Aopen&template=${templateWithQuery.id}`,
    )
  })
})

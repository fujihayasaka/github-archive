import {act, screen} from '@testing-library/react'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {
  EditSecurityCampaignFormDialog,
  type EditSecurityCampaignFormDialogProps,
} from '../../components/EditSecurityCampaignFormDialog'
import {getEditSecurityCampaignFormDialogProps, getSecurityCampaign} from '../../test-utils/mock-data'
import type {SecurityCampaignForm} from '../../types/security-campaign'
import {ApiError} from '../../utils/api-error'

const render = (props?: Partial<EditSecurityCampaignFormDialogProps>) =>
  reactRender(<EditSecurityCampaignFormDialog {...getEditSecurityCampaignFormDialogProps(props)} />)

test('The dialog shows the general tab by default', () => {
  render()

  const generalTab = screen.getByText('General')
  expect(generalTab).toBeInTheDocument()
  expect(generalTab).toBeEnabled()
})

test('The dialog shows the filters tab', () => {
  render()

  const filtersTab = screen.getByText('Filters')
  expect(filtersTab).toBeInTheDocument()
})

test('The dialog shows the repositories tab', () => {
  render()

  const repositoriesTab = screen.getByText('Repositories')
  expect(repositoriesTab).toBeInTheDocument()
})

test('The dialog shows campaign details', () => {
  const propsCampaign = getSecurityCampaign()
  render({campaign: getSecurityCampaign()})

  const nameInput = getCampaignNameInput()
  expect(nameInput).toBeInTheDocument()
  expect(nameInput.tagName).toBe('INPUT')
  expect(nameInput).toHaveValue('User-controlled code injection')
  expect(nameInput).toBeEnabled()
  expect(nameInput).toHaveProperty('type', 'text')

  const descriptionInput = getCampaignDescriptionInput()
  expect(descriptionInput).toBeInTheDocument()
  expect(descriptionInput.tagName).toBe('TEXTAREA')
  expect(descriptionInput).toHaveValue(
    'Directly evaluating user input (for example, an HTTP request parameter) as code without first sanitizing the input allows an attacker arbitrary code execution.',
  )
  expect(descriptionInput).toBeEnabled()

  const dueDateInput = getCampaignDueDateButton()
  expect(dueDateInput).toBeInTheDocument()
  expect(dueDateInput.tagName).toBe('BUTTON')
  expect(dueDateInput).toBeEnabled()

  const campaignManagerInput = getCampaignManagerButton()
  expect(campaignManagerInput).toBeInTheDocument()
  expect(campaignManagerInput.tagName).toBe('BUTTON')
  expect(campaignManagerInput).toBeEnabled()
  expect(campaignManagerInput).toHaveTextContent('monalisa')

  const contactLinkInput = getContactLinkInput()
  expect(contactLinkInput).toBeInTheDocument()
  expect(contactLinkInput.tagName).toBe('INPUT')
  expect(contactLinkInput).toHaveValue(propsCampaign.contactLink)
  expect(contactLinkInput).toBeEnabled()
  expect(contactLinkInput).toHaveProperty('type', 'text')
})

test('the campaign manager defaults to the campaign manager', () => {
  render()

  const campaignManagerInput = getCampaignManagerButton()
  expect(campaignManagerInput).toHaveTextContent('monalisa')
})

test('The dialog has a cancel button that closes the dialog', () => {
  const setIsOpen = jest.fn()
  render({
    setIsOpen,
  })

  const cancelButton = screen.getByRole('button', {
    name: 'Cancel',
  })

  expect(cancelButton).toBeInTheDocument()
  expect(cancelButton).toBeEnabled()

  act(() => {
    cancelButton.click()
  })

  expect(setIsOpen).toHaveBeenCalledWith(false)
})

test('The submit button is enabled by default', () => {
  render()

  const updateButton = getUpdateButton()

  expect(updateButton).toBeInTheDocument()
  expect(updateButton).toBeEnabled()
})

test('The submit button is disabled if the campaign name is cleared', async () => {
  const {user} = render()

  const nameInput = getCampaignNameInput()
  await user.clear(nameInput)

  expect(getUpdateButton()).toBeDisabled()
})

test('The submit button is disabled if the campaign description is cleared', async () => {
  const {user} = render()

  // Fill in all inputs except description (campaign manager is pre-filled)
  const descriptionInput = getCampaignDescriptionInput()
  await user.clear(descriptionInput)

  expect(getUpdateButton()).toBeDisabled()
})

test('Calls the submitForm callback with unchanged values when the form is submitted with an existing campaign', async () => {
  const campaign = getSecurityCampaign()
  const campaignForm: SecurityCampaignForm = {
    name: campaign.name,
    description: campaign.description,
    endsAt: campaign.endsAt,
    managers: campaign.managers,
    teamManagers: [],
    generateAutofixPullRequests: false,
    generateIssues: false,
    contactLink: campaign.contactLink,
  }

  const submitForm = jest.fn().mockResolvedValue({ok: true})
  const setIsOpen = jest.fn()
  const {user} = render({
    submitForm,
    setIsOpen,
  })

  await user.click(getUpdateButton())

  expect(submitForm).toHaveBeenCalledWith(campaignForm, {
    onSuccess: expect.any(Function),
  })
})

test('Shows an error message when an error message is given', async () => {
  const {user} = render({
    submitForm: jest.fn(),
    formError: new ApiError('Something went wrong', {} as Response),
  })

  await user.type(getCampaignNameInput(), 'My campaign')
  await user.type(getCampaignDescriptionInput(), 'My campaign description')

  await user.click(getUpdateButton())

  expect(screen.getByText('Something went wrong')).toBeInTheDocument()
})

test('Shows campaign details when readOnly is true', () => {
  const campaign = getSecurityCampaign()
  render({
    campaign,
    readOnly: true,
  })

  const title = screen.getByText('Campaign details')
  expect(title).toBeInTheDocument()

  const nameInput = getCampaignNameInput()
  expect(nameInput).toBeInTheDocument()
  expect(nameInput).toHaveValue(campaign.name)
  expect(nameInput).toBeDisabled()

  const descriptionInput = getCampaignDescriptionInput()
  expect(descriptionInput).toBeInTheDocument()
  expect(descriptionInput).toHaveValue(campaign.description)
  expect(descriptionInput).toBeDisabled()

  const dueDateInput = getCampaignDueDateButton()
  expect(dueDateInput).toBeInTheDocument()
  expect(dueDateInput).toBeDisabled()

  const campaignManagerInput = getCampaignManagerButton()
  expect(campaignManagerInput).toBeInTheDocument()
  expect(campaignManagerInput).toHaveTextContent('monalisa')

  const contactLinkInput = getContactLinkInput()
  expect(contactLinkInput).toBeInTheDocument()
  expect(contactLinkInput).toHaveValue(campaign.contactLink)
  expect(contactLinkInput).toBeDisabled()

  const closeButton = screen.getAllByRole('button', {
    name: 'Close',
  })[1]
  expect(closeButton).toBeInTheDocument()
  expect(closeButton).toBeEnabled()

  const saveButton = screen.queryByRole('button', {
    name: 'Save changes',
  })
  expect(saveButton).not.toBeInTheDocument()
})

test('It shows the validation error when the contact link is invalid', async () => {
  const {user} = render()

  const contactLinkInput = getContactLinkInput()
  await user.click(contactLinkInput)
  await user.paste('invalid link')

  expect(screen.getByText('Contact link must use http, https or mailto scheme')).toBeInTheDocument()
})

function getUpdateButton() {
  return screen.getByRole('button', {
    name: 'Save changes',
  })
}

function getCampaignNameInput() {
  return screen.getByPlaceholderText('A short and descriptive name for this security campaign.')
}

function getCampaignDescriptionInput() {
  return screen.getByPlaceholderText(
    "Let everybody know what this security campaign is about and why it's important to remediate these alerts.",
  )
}

function getContactLinkInput() {
  return screen.getByPlaceholderText('Provide a link for contacting the campaign managers.')
}

function getCampaignDueDateButton() {
  return screen.getByLabelText(/date picker/i)
}

function getCampaignManagerButton() {
  return screen.getByLabelText('Campaign manager', {exact: false})
}

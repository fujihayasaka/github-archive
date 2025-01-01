import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {ModelsShowRoute} from '../ModelsShowRoute'
import {mockShowModelPayload} from '../components/__tests__/mocks'
import {mockGettingStartedPayload, mockModel} from '../../playground/__tests__/mocks'

describe('ModelsShowRoute', () => {
  test('renders model information', () => {
    const tag = 'caffeinated'
    const summary = 'This model will change your mind about coffee.'
    const trainingDataDate = '2021-02-03'
    const model = Object.assign({}, mockModel, {
      tags: [tag],
      rate_limit_tier: 'grande',
      summary,
      training_data_date: trainingDataDate,
    })
    const routePayload = mockShowModelPayload({model})

    const {container} = render(<ModelsShowRoute />, {routePayload})

    expect(within(container).getByTestId('feedback-link')).toBeInTheDocument()
    expect(within(container).getByTestId('publisher-avatar')).toBeInTheDocument()
    expect(within(container).getAllByTestId('model-details')).toHaveLength(1)
    const rateLimitTierElements = within(container).getAllByTestId('rate-limit-tier')
    expect(rateLimitTierElements).toHaveLength(1)
    for (const rateLimitTierEl of rateLimitTierElements) {
      expect(within(rateLimitTierEl).getByRole('link', {name: 'Grande'})).toBeInTheDocument()
    }
    expect(within(container).getByRole('heading', {name: model.friendly_name, level: 1})).toBeInTheDocument()
    const tagsSections = within(container).getAllByTestId('tags-section')
    expect(tagsSections).toHaveLength(1)
    for (const tagsSection of tagsSections) {
      expect(within(tagsSection).getByRole('heading', {name: 'Tags', level: 3})).toBeInTheDocument()
      expect(within(tagsSection).getByRole('link', {name: tag})).toBeInTheDocument()
    }
    expect(within(container).getAllByRole('heading', {name: 'Languages', level: 3})).toHaveLength(1)
    expect(within(container).getByRole('heading', {name: 'About', level: 3})).toBeInTheDocument()
    expect(within(container).getByRole('link', {name: 'Playground'})).toBeInTheDocument()
    expect(within(container).getByRole('navigation', {name: 'Model navigation'})).toBeInTheDocument()
    expect(within(container).getAllByRole('link', {name: model.task})).toHaveLength(1)
    expect(within(container).getByTestId('get-api-key-button')).toBeInTheDocument()
    expect(within(container).getByRole('img', {name: model.publisher})).toBeInTheDocument()
    expect(within(container).getByTestId('summary')).toHaveTextContent(summary)
    const trainingDateElements = within(container).getAllByTestId('training-date')
    expect(trainingDateElements).toHaveLength(1)
    for (const trainingDateEl of trainingDateElements) {
      expect(trainingDateEl).toHaveTextContent(trainingDataDate)
    }
    expect(within(container).getAllByTestId('languages')).toHaveLength(1)
  })

  test('renders header breadcrumbs when logged out', () => {
    const model = mockModel
    const routePayload = mockShowModelPayload({model, isLoggedIn: false})
    const {container} = render(<ModelsShowRoute />, {routePayload})

    expect(within(container).getByRole('link', {name: 'Marketplace'})).toBeInTheDocument()
    expect(within(container).getByRole('link', {name: 'Models'})).toBeInTheDocument()
    expect(within(container).getByRole('navigation', {name: 'Breadcrumbs'})).toBeInTheDocument()
  })

  test('renders README tab by default', () => {
    const readme = 'Let me tell you the ways of the iced shaken espresso.'
    const routePayload = mockShowModelPayload({model: mockModel, modelReadme: readme as SafeHTMLString})

    const {container} = render(<ModelsShowRoute />, {routePayload})

    expect(within(container).getByTestId('readme-content')).toHaveTextContent(readme)
    expect(within(container).queryByTestId('license-content')).not.toBeInTheDocument()
    expect(within(container).queryByTestId('transparency-content')).not.toBeInTheDocument()
    expect(within(container).queryByTestId('evaluation-content')).not.toBeInTheDocument()
    expect(within(container).getByTestId('readme-hero')).toBeInTheDocument()
  })

  test('renders Evaluation tab when specified', () => {
    const evaluation = 'I have tried the lattes, cappuccinos, and macchiatos. I prefer this drink.'
    const routePayload = mockShowModelPayload({modelEvaluation: evaluation as SafeHTMLString})

    const {container} = render(<ModelsShowRoute />, {routePayload, search: '?tab=evaluation'})

    expect(within(container).getByTestId('evaluation-content')).toHaveTextContent(evaluation)
    expect(within(container).queryByTestId('license-content')).not.toBeInTheDocument()
    expect(within(container).queryByTestId('transparency-content')).not.toBeInTheDocument()
    expect(within(container).queryByTestId('readme-content')).not.toBeInTheDocument()
    expect(within(container).queryByTestId('readme-hero')).not.toBeInTheDocument()
    const modelNav = within(container).getByRole('navigation', {name: 'Model navigation'})
    expect(modelNav).toBeInTheDocument()
    const evaluationLink = within(modelNav).getByRole('link', {name: 'Evaluation'})
    expect(evaluationLink).toBeInTheDocument()
    expect(evaluationLink).toHaveAttribute('aria-current', 'page')
    const otherNavLinks = [
      within(modelNav).getByRole('link', {name: 'README'}),
      within(modelNav).getByRole('link', {name: 'Transparency'}),
      within(modelNav).getByRole('link', {name: 'License'}),
    ]
    for (const link of otherNavLinks) {
      expect(link).toBeInTheDocument()
      expect(link).not.toHaveAttribute('aria-current', 'page')
    }
  })

  test('renders Transparency tab when specified', () => {
    const transparency = 'This drink is made with espresso and milk.'
    const routePayload = mockShowModelPayload({modelTransparencyContent: transparency as SafeHTMLString})

    const {container} = render(<ModelsShowRoute />, {routePayload, search: '?tab=transparency'})

    expect(within(container).getByTestId('transparency-content')).toHaveTextContent(transparency)
    expect(within(container).queryByTestId('license-content')).not.toBeInTheDocument()
    expect(within(container).queryByTestId('evaluation-content')).not.toBeInTheDocument()
    expect(within(container).queryByTestId('readme-content')).not.toBeInTheDocument()
    expect(within(container).queryByTestId('readme-hero')).not.toBeInTheDocument()
    const modelNav = within(container).getByRole('navigation', {name: 'Model navigation'})
    expect(modelNav).toBeInTheDocument()
    const transparencyLink = within(modelNav).getByRole('link', {name: 'Transparency'})
    expect(transparencyLink).toBeInTheDocument()
    expect(transparencyLink).toHaveAttribute('aria-current', 'page')
    const otherNavLinks = [
      within(modelNav).getByRole('link', {name: 'README'}),
      within(modelNav).getByRole('link', {name: 'Evaluation'}),
      within(modelNav).getByRole('link', {name: 'License'}),
    ]
    for (const link of otherNavLinks) {
      expect(link).toBeInTheDocument()
      expect(link).not.toHaveAttribute('aria-current', 'page')
    }
  })

  test('renders License tab when specified', () => {
    const license = 'French Press 3.0'
    const routePayload = mockShowModelPayload({modelLicense: license as SafeHTMLString})

    const {container} = render(<ModelsShowRoute />, {routePayload, search: '?tab=license'})

    expect(within(container).getByTestId('license-content')).toHaveTextContent(license)
    expect(within(container).queryByTestId('transparency-content')).not.toBeInTheDocument()
    expect(within(container).queryByTestId('evaluation-content')).not.toBeInTheDocument()
    expect(within(container).queryByTestId('readme-content')).not.toBeInTheDocument()
    expect(within(container).queryByTestId('readme-hero')).not.toBeInTheDocument()
    const modelNav = within(container).getByRole('navigation', {name: 'Model navigation'})
    expect(modelNav).toBeInTheDocument()
    const licenseLink = within(modelNav).getByRole('link', {name: 'License'})
    expect(licenseLink).toBeInTheDocument()
    expect(licenseLink).toHaveAttribute('aria-current', 'page')
    const otherNavLinks = [
      within(modelNav).getByRole('link', {name: 'README'}),
      within(modelNav).getByRole('link', {name: 'Evaluation'}),
      within(modelNav).getByRole('link', {name: 'Transparency'}),
    ]
    for (const link of otherNavLinks) {
      expect(link).toBeInTheDocument()
      expect(link).not.toHaveAttribute('aria-current', 'page')
    }
  })

  // https://github.com/github/github/pull/353703
  test('allows clicking button to get API key', async () => {
    const routePayload = mockGettingStartedPayload()

    const {container, user} = render(<ModelsShowRoute />, {routePayload})

    const getApiKeyButton = within(container).getByTestId('get-api-key-button')
    expect(getApiKeyButton).toBeInTheDocument()
    expect(screen.queryByRole('dialog', {name: 'Get API key'})).not.toBeInTheDocument()

    await user.click(getApiKeyButton)

    expect(screen.getByRole('dialog', {name: 'Get API key'})).toBeInTheDocument()
  }, 5000)
})

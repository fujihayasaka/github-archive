import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {LanguagesSection} from '../LanguagesSection'

describe('LanguagesSection', () => {
  test('renders', () => {
    const {container} = render(<LanguagesSection languages={['fr', 'it', 'pt']} />)

    expect(within(container).getByRole('heading', {name: 'Languages', level: 3})).toBeInTheDocument()
    expect(within(container).getByTestId('languages')).toHaveTextContent('French, Italian, and Portuguese')
    expect(within(container).queryByRole('button', {name: 'Reveal all languages'})).not.toBeInTheDocument()
  })

  test('renders with specified heading level', () => {
    const {container} = render(<LanguagesSection headingLevel="h2" languages={['pa']} />)

    expect(within(container).getByRole('heading', {name: 'Languages', level: 2})).toBeInTheDocument()
    expect(within(container).getByTestId('languages')).toHaveTextContent('Punjabi')
    expect(within(container).queryByRole('button', {name: 'Reveal all languages'})).not.toBeInTheDocument()
  })

  test('truncates languages list when there are too many', async () => {
    const {container, user} = render(
      <LanguagesSection
        languages={['fr', 'it', 'pt', 'en', 'pl', 'pa', 'hr', 'zh-tw', 'da', 'ar-kw', 'ga', 'ko', 'es-ec', 'zu']}
      />,
    )

    expect(within(container).getByRole('heading', {name: 'Languages', level: 3})).toBeInTheDocument()
    expect(within(container).getByTestId('languages')).toHaveTextContent(
      'French, Italian, Portuguese, English, Polish, Punjabi, Croatian, Chinese (Taiwan), Danish, Arabic (Kuwait), Irish, Korean',
    )
    const revealLangButton = within(container).getByRole('button', {name: 'Reveal all languages'})
    expect(revealLangButton).toBeInTheDocument()

    await user.click(revealLangButton)

    expect(within(container).getByTestId('languages')).toHaveTextContent(
      'French, Italian, Portuguese, English, Polish, Punjabi, Croatian, Chinese (Taiwan), Danish, Arabic (Kuwait), Irish, Korean, Spanish (Ecuador), and Zulu',
    )
  })
})

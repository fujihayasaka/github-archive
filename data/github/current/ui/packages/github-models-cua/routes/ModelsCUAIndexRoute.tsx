import {useState} from 'react'
import {appBuilder} from '../config/app'
import {ActionList, ActionMenu, Button, FormControl, PageLayout, Textarea, TextInput} from '@primer/react'
import {MarkGithubIcon, PaperAirplaneIcon} from '@primer/octicons-react'
import {useNavigate} from '@github-ui/use-navigate'
import {useSearchParams} from 'react-router-dom'

export const modelsCUAIndexRoute = appBuilder.createQueryRouteConfig('modelsCUAIndexRoute', {
  path: '/models/cua',
  index: true,
})

export default function Page() {
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()

  const [prompt, setPrompt] = useState(searchParams.get('prompt') || '')
  const [menuOpen, setMenuOpen] = useState(false)

  const [showUrlError, setShowUrlError] = useState(false)
  const [showPromptError, setShowPromptError] = useState(false)

  const onSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault()

    const formData = new FormData(e.currentTarget)
    const url = formData.get('url') as string

    setShowUrlError(false)
    setShowPromptError(false)

    if (!url) setShowUrlError(true)
    if (!prompt) setShowPromptError(true)

    if (url && prompt) {
      navigate({
        pathname: '/models/cua/session',
        search: `?prompt=${encodeURIComponent(prompt)}&url=${encodeURIComponent(url)}`,
      })
    }
  }

  return (
    <PageLayout>
      <PageLayout.Content data-hpc as="div" width="medium">
        <div className="text-center mb-4">
          <details>
            <summary style={{listStyle: 'none'}}>
              <MarkGithubIcon size={128} className="mt-4 pb-4" aria-label="GitHub logo" />
            </summary>
            <div className="color-fg-muted text-mono text-left f6">
              <ol>
                <li>
                  Run:{' '}
                  <pre>
                    az ml online-endpoint get-credentials --subscription 9ec1d932-0f3f-486c-acc6-e7d78b358f9b --name
                    ea-cua-inference --resource-group oai_research_rg --workspace-name ppp_test
                  </pre>
                </li>
                <li>
                  Paste token here:{' '}
                  <input
                    aria-label="The token input"
                    type="text"
                    onChange={e => {
                      localStorage['models_cua_token_override'] = e.target.value
                    }}
                  />
                </li>
                <li>Refresh the page</li>
              </ol>
            </div>
          </details>
          <h1 className="pb-4">GitHub Models Computer User Agent</h1>
          <p className="color-fg-muted">
            Need feedback on your website? Just paste the URL and a prompt, and let the AI do the rest. CUA will analyze
            the page and provide feedback that will let you get the most out of your site.
          </p>
          <p className="color-fg-muted">Choose one of our templates to get started, or create your own!</p>
        </div>
        <form className="d-flex flex-column gap-3 mt-3" onSubmit={onSubmit}>
          <FormControl required className="flex-1">
            <FormControl.Label>Website</FormControl.Label>
            <TextInput
              defaultValue={searchParams.get('url') || ''}
              name="url"
              className="width-full"
              placeholder="Enter website URL"
            />
            {showUrlError && <FormControl.Validation variant="error">Please enter a URL.</FormControl.Validation>}
          </FormControl>

          <FormControl required>
            <FormControl.Label>Prompt</FormControl.Label>
            <Textarea
              className="width-full"
              resize="vertical"
              cols={80}
              value={prompt}
              onChange={e => setPrompt(e.target.value)}
              placeholder="Enter prompt"
            />
            {showPromptError && <FormControl.Validation variant="error">Please enter a prompt.</FormControl.Validation>}
          </FormControl>
          <div className="d-flex flex-justify-between">
            <ActionMenu open={menuOpen} onOpenChange={setMenuOpen}>
              <ActionMenu.Button>Prompt templates</ActionMenu.Button>
              <ActionMenu.Overlay>
                <ActionList>
                  {promptTemplates.map(template => (
                    <ActionList.Item
                      key={template.name}
                      onSelect={() => {
                        setPrompt(template.prompt)
                        setMenuOpen(false)
                      }}
                    >
                      {template.name}
                    </ActionList.Item>
                  ))}
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
            <Button variant="primary" trailingVisual={PaperAirplaneIcon} type="submit">
              Launch
            </Button>
          </div>
        </form>
      </PageLayout.Content>
    </PageLayout>
  )
}

const promptTemplates = [
  {
    name: 'Functionality',
    prompt: `Web Testing Guidelines
A web tester ensures a website is functional, user-friendly, and secure. You will have separate testing schemes. In this scheme, focus on this key area:

**Functionality Testing**
- Check all Side menu/Navigation panel/ buttons first.
- Ensure the search functionality works correctly.
- Check that all links (internal and external) are functional and correct.
- Ensure buttons trigger the correct actions.
- Test login, session handling, and database interactions.

Providing Feedback on the above perspective. Suggest clear, actionable changes to enhance clarity and engagement.
`,
  },
  {
    name: 'Vision consistency',
    prompt: `Web Testing Guidelines
A web tester ensures a website is functional, user-friendly, and secure. You will have separate testing schemes. In this scheme, focus on this key area:

**Visual Consistency**
- For celebrities, make sure the profile image matched the celebrity identity. If not, please search from wikimedia for correct figures and report the URLs of the raw images in json format in the final feedback. It is for internal testing and we will skip the license for now.
- For other figure, make sure the visual content is consistent with the caption.
- Return the clipboard contents, and include all image URLs in the final feedback.
- The expected URL should start with: https://upload.wikimedia.org/

Providing Feedback on the above perspective. Suggest clear, actionable changes to enhance clarity and engagement.
`,
  },
  {
    name: 'UI Design',
    prompt: `Web Testing Guidelines
A web tester ensures a website is functional, user-friendly, and secure. You will have separate testing schemes. In this scheme, focus on this key area:

**UI/UX Testing**
- Visual Evaluation
    - Ensure consistency in fonts, colors, and layouts.
    - Ensure proper spacing, padding, and alignment.
    - Maintain a balanced contrast for readability.

- Layout & Structure
    - Keep a clear and logical content hierarchy.
    - Avoid clutter—prioritize essential elements.
    - Ensure sections are well-defined and easy to scan.

- Accessibility & Readability
    - Use legible fonts with proper size and line spacing.
    - Ensure color contrast meets accessibility standards.
    - Support keyboard navigation and screen readers.

Providing Feedback on the perspective. Suggest clear, actionable changes to enhance clarity and engagement.
`,
  },
]

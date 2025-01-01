import type {
  CustomCopilotGitHubIssueResource,
  CustomCopilotGitHubPullRequestResource,
  CustomCopilotResource,
} from '@github-ui/custom-copilots/types'
import {type SafeHTMLString, SafeHTMLText} from '@github-ui/safe-html'
import {ScopedCommands} from '@github-ui/ui-commands'
import {useDebounce} from '@github-ui/use-debounce'
import {PlusIcon, TrashIcon} from '@primer/octicons-react'
import {Button, Dialog, FormControl, IconButton, Stack, TextInput} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {useEffect, useState} from 'react'

import type {UrlResourceValidationError} from './hooks/use-validate-url-resources'
import {UrlDetails, useValidateUrlResources} from './hooks/use-validate-url-resources'

interface GitHubUrlDialogProps {
  onClose: () => void
  onSave: (resources: Array<CustomCopilotGitHubPullRequestResource | CustomCopilotGitHubIssueResource>) => void
  resourcesToSave?: CustomCopilotResource[]
  owner: string | undefined
}

export function GitHubUrlDialog({onClose, onSave, resourcesToSave, owner}: GitHubUrlDialogProps) {
  // const [isSaving, setIsSaving] = useState(false)
  const [urls, setUrls] = useState<UrlDetails[]>(() => [new UrlDetails(crypto.randomUUID())])
  const [errorState, setErrorState] = useState(false)

  const {validateUrlResources} = useValidateUrlResources()

  const handleSubmit = (e?: React.FormEvent<HTMLElement>) => {
    e?.preventDefault()
    void updateUrlResources()
  }

  const updateUrlResources = async () => {
    setErrorState(false)

    // If any of the URLs have no value, or unknown type, set them as invalid
    const invalidUrls = urls.filter(url => url.url === '' || url.type === 'unknown' || (owner && url.owner !== owner))
    if (invalidUrls.length > 0) {
      const updatedUrls = urls.map(url => {
        if (owner && url.owner && url.owner !== owner) {
          return {...url, errorMessage: `This doesn't belong to the ${owner} organization.`}
        } else if (invalidUrls.some(invalid => invalid.id === url.id)) {
          return {...url, errorMessage: 'Invalid URL'}
        }
        return url
      })

      setUrls(updatedUrls)
      setErrorState(true)
      return
    }

    let deDuplicatedUrls = urls
    // If there are any duplicate URLs, filter them out
    if (resourcesToSave !== undefined) {
      const currentUrls = resourcesToSave.filter(
        resource => resource.type === 'github_issue' || resource.type === 'github_pull_request',
      )
      deDuplicatedUrls = urls.filter(
        url =>
          !currentUrls.some(
            currentUrl =>
              currentUrl.nwo === `${url.owner}/${url.repo}` &&
              currentUrl.number === url.number &&
              currentUrl.type === url.type,
          ),
      )
    }

    const urlResources = deDuplicatedUrls.map(url => {
      const resource = {
        id: url.id,
        owner: url.owner,
        repo: url.repo,
        number: url.number,
        type: url.type as 'github_issue' | 'github_pull_request',
        url: url.url,
        errorMessage: url.errorMessage,
      }
      return resource
    })

    if (urlResources.length === 0) {
      onClose()
      return
    }

    try {
      const res = await validateUrlResources({input: urlResources, spaceOwner: owner})
      onSave(res)
      onClose()
    } catch (errors: unknown) {
      // If errors are caught, one or more URLs are invalid
      if (Array.isArray(errors)) {
        for (const error of errors as UrlResourceValidationError[]) {
          const resource = urls.find(r => r.id === error.id)
          if (resource) {
            resource.errorMessage = 'Resource not found'
          }
        }
        setErrorState(true)
      }
    }
  }

  const AddUrlTextInputRow = () => {
    setUrls([...urls, new UrlDetails(crypto.randomUUID())])
  }

  const removeUrlTextInputRow = (index: number) => {
    const tmpUrls = [...urls]
    tmpUrls.splice(index, 1)
    setUrls(tmpUrls)
  }

  const onUrlChange = (index: number, value: string) => {
    // Will need to add a loading state so users do not submit the dialog before the urls are parsed
    const tmpUrls = [...urls]
    // use the existing empty UrlDetails object if it exists
    const parsedUrl = parseUrl(value, tmpUrls[index] || new UrlDetails(crypto.randomUUID()))
    tmpUrls[index] = parsedUrl
    setUrls(tmpUrls)
  }

  const parseUrl = (url: string, urlDetails: UrlDetails) => {
    // A very naive implementation for now until we implement validations
    // Copilot wrote this regex
    const issueRegex = /\/([^/]+)\/([^/]+)\/issues\/(\d+)/
    const prRegex = /\/([^/]+)\/([^/]+)\/pull\/(\d+)/

    const issueMatch = url.match(issueRegex)
    const prMatch = url.match(prRegex)

    urlDetails.url = url
    if (issueMatch) {
      urlDetails.owner = issueMatch[1] ?? ''
      urlDetails.repo = issueMatch[2] ?? ''
      urlDetails.number = parseInt(issueMatch[3] ?? '0', 10)
      urlDetails.type = 'github_issue'
    } else if (prMatch) {
      urlDetails.owner = prMatch[1] ?? ''
      urlDetails.repo = prMatch[2] ?? ''
      urlDetails.number = parseInt(prMatch[3] ?? '0', 10)
      urlDetails.type = 'github_pull_request'
    }
    return urlDetails
  }

  return (
    <Dialog
      width="large"
      title="Add via GitHub URL"
      onClose={onClose}
      renderFooter={() => (
        <Dialog.Footer>
          <div className="d-flex flex-row flex-justify-end gap-2">
            <Button onClick={onClose}>Cancel</Button>
            <Button variant="primary" onClick={handleSubmit} loadingAnnouncement="Saving resource">
              Add
            </Button>
          </div>
        </Dialog.Footer>
      )}
    >
      {errorState && <Banner title="Failed to save URL(s)" variant="critical" className="mb-2" />}
      <p>
        Paste the URLs of the GitHub content{' '}
        {owner && <SafeHTMLText html={`from the <b>${owner}</b> organization` as SafeHTMLString} />} you want to add.
        You can include issues and pull requests.
      </p>
      <ScopedCommands commands={{'github:submit-form': () => handleSubmit()}}>
        <form onSubmit={handleSubmit}>
          <Stack direction="vertical" align="center">
            {urls.map((url, i) => (
              <div style={{width: '100%'}} key={url.id}>
                <UrlTextInputRow
                  index={i}
                  removeUrlTextInputRow={removeUrlTextInputRow}
                  inputCount={urls.length}
                  updateUrls={onUrlChange}
                  urlValue={url.url}
                />
                {errorState && url.errorMessage !== undefined && (
                  <FormControl.Validation variant="error">{url.errorMessage}</FormControl.Validation>
                )}
              </div>
            ))}
          </Stack>
        </form>
      </ScopedCommands>
      <Button leadingVisual={PlusIcon} className="mt-3" onClick={AddUrlTextInputRow}>
        Add another
      </Button>
    </Dialog>
  )
}

function UrlTextInputRow({
  index,
  removeUrlTextInputRow,
  inputCount,
  updateUrls,
  urlValue,
}: {
  index: number
  removeUrlTextInputRow: (index: number) => void
  inputCount: number
  updateUrls: (index: number, value: string) => void
  urlValue: string
}) {
  const [url, setUrl] = useState<string>(urlValue)

  // Update the state when urlValue changes from removing a row
  useEffect(() => {
    setUrl(urlValue)
  }, [urlValue])

  const onChangeUrl = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value
    setUrl(value)
    debouncedSetUrl(value)
  }

  const debouncedSetUrl = useDebounce((value: string) => {
    updateUrls(index, value)
  }, 400)

  return (
    <FormControl className="d-flex flex-row flex-justify-between flex-items-center width-full">
      <FormControl.Label visuallyHidden>URL</FormControl.Label>
      <TextInput
        placeholder="https://github.com/mona/playground/issues/123"
        value={url}
        onChange={onChangeUrl}
        className="width-full"
      />
      {inputCount > 1 && (
        <IconButton
          icon={TrashIcon}
          variant="invisible"
          aria-label="Remove url"
          className="ml-2"
          onClick={() => removeUrlTextInputRow(index)}
        />
      )}
    </FormControl>
  )
}

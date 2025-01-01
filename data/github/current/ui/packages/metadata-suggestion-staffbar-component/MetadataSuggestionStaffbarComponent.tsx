import {useExternalAnchor, type ReactPartialAnchorProps} from '@github-ui/react-core/react-partial-anchor'
import {Textarea, Button, SegmentedControl} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {useSafeAsyncCallback} from '@github-ui/use-safe-async-callback'
import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {LabelToken} from '@github-ui/label-token'
import {useCallback, useRef, useState} from 'react'
import {labelsPrompt, issueTypePrompt} from '@github-ui/issue-metadata/issueClassifierUserPrompts'

export interface MetadataSuggestionStaffbarComponentProps extends ReactPartialAnchorProps {
  repositoryLabels: Array<{name: string; description: string; color: string}>
  repositoryTypes: Array<{name: string; description: string}>
  issueId: string
  issueTitle: string
  issueBody: string
}

export function MetadataSuggestionStaffbarComponent({
  repositoryLabels,
  repositoryTypes,
  issueId,
  issueTitle,
  issueBody,
  reactPartialAnchor,
}: MetadataSuggestionStaffbarComponentProps) {
  if (!reactPartialAnchor) {
    throw new Error('MetadataSuggestionStaffbarComponent must be wrapped in a ReactPartialAnchorElement')
  }

  const [selectedType, setSelectedType] = useState(0)
  const [customLabelsPrompt, setCustomLabelsPrompt] = useState(labelsPrompt)
  const [customIssueTypePrompt, setCustomIssueTypePrompt] = useState(() =>
    issueTypePrompt(repositoryTypes.map(n => n.name).join('\n')),
  )
  const {open, setOpen} = useExternalAnchor(reactPartialAnchor)
  const onDialogClose = useCallback(() => setOpen(false), [setOpen])
  const authTokenProvider = useRef(new CopilotAuthTokenProvider([]))
  const [copilotRequestSuccess, setCopilotRequestSuccess] = useState<'success' | 'error' | 'loading' | 'new'>('new')
  const [copilotLabels, setCopilotLabels] = useState<
    Array<{name: string; description: string; color: string; confidence: number} | null>
  >([])

  const makeCopilotRequest = useSafeAsyncCallback(async () => {
    setCopilotRequestSuccess('loading')
    try {
      const token = await authTokenProvider.current.getAuthToken()
      const requestPath = 'https://api.githubcopilot.com/agents/github-classifier' // default request path for Copilot API classifier agent

      const copilot_references =
        selectedType === 0
          ? [
              {
                id: issueId.toString(),
                type: 'github.issue',
                data: {
                  type: 'issue',
                  title: issueTitle,
                  body: issueBody,
                  labels: repositoryLabels?.map(l => {
                    return {name: l.name, description: l.description}
                  }),
                },
              },
            ]
          : [
              {
                id: issueId.toString(),
                data: {
                  title: issueTitle,
                  body: issueBody,
                },
              },
            ]

      const headers: {[key: string]: string} = {
        Authorization: token.authorizationHeaderValue,
        'copilot-integration-id': 'copilot-embedded-experience',
        'Content-Type': 'application/json',
      }

      const requestBody = {
        messages: [
          {
            role: 'user',
            content: selectedType === 0 ? customLabelsPrompt : customIssueTypePrompt,
            copilot_references,
          },
        ],
      }

      const result = await fetch(requestPath, {
        method: 'POST',
        mode: 'cors',
        cache: 'no-cache',
        headers,
        body: JSON.stringify(requestBody),
      })

      if (result.ok) {
        // Parse the response and extract the classification results
        const res = (await result.text()).split('\n')[0]?.substring(6)
        if (res) {
          // Parse the classification result in JSON format for easier use
          const resultJson = JSON.parse(JSON.parse(res).choices[0].message.content)
          const resultJsonNames = Object.keys(resultJson)
          let matchingData = Array<{name: string; color: string; description: string; confidence: number} | null>()

          if (selectedType === 1) {
            matchingData = repositoryTypes.map(type => {
              if (resultJsonNames.includes(type.name))
                return {
                  name: type.name,
                  color: '00FFFFFF',
                  description: type.description,
                  confidence: resultJson[type.name],
                }
              return null
            })
          } else {
            matchingData = repositoryLabels.map(label => {
              if (resultJsonNames.includes(label.name))
                return {
                  name: label.name,
                  color: label.color,
                  description: label.description,
                  confidence: resultJson[label.name],
                }
              return null
            })
          }
          setCopilotLabels(matchingData)
        }
        setCopilotRequestSuccess('success')
      } else {
        setCopilotRequestSuccess('error')
      }
    } catch {
      setCopilotRequestSuccess('error')
    }
  })

  return (
    <>
      {open ? (
        <Dialog onClose={onDialogClose} title="Issue Metadata Suggestions" width="xlarge">
          <SegmentedControl aria-label="Toggle between labels and issue types" onChange={i => setSelectedType(i)}>
            <SegmentedControl.Button selected={selectedType === 0}>Labels</SegmentedControl.Button>
            <SegmentedControl.Button selected={selectedType === 1}>Type</SegmentedControl.Button>
          </SegmentedControl>
          <Dialog.Body className="d-flex flex-column gap-3">
            <span className="d-flex flex-column gap-1">
              <span>Custom prompt</span>
              <Textarea
                value={selectedType === 0 ? customLabelsPrompt : customIssueTypePrompt}
                onChange={e =>
                  selectedType === 0 ? setCustomLabelsPrompt(e.target.value) : setCustomIssueTypePrompt(e.target.value)
                }
                cols={100}
              />
            </span>
            <Button variant="primary" onClick={makeCopilotRequest} disabled={copilotRequestSuccess === 'loading'}>
              Get copilot suggested <>{selectedType === 0 ? 'labels' : 'issue types'}</> for issue
            </Button>
            {copilotRequestSuccess === 'success' && (
              <table className="site-admin-table">
                <thead>
                  <tr>
                    <th>Label</th>
                    <th>Confidence</th>
                  </tr>
                </thead>
                <tbody>
                  {copilotLabels.map(label => {
                    if (label) {
                      return (
                        <tr key={label.name}>
                          <td>
                            <LabelToken
                              text={label.name}
                              fillColor={`#${label.color}`}
                              style={{
                                overflow: 'hidden',
                                textOverflow: 'ellipsis',
                                cursor: 'pointer',
                                maxWidth: '100%',
                              }}
                            />
                          </td>
                          <td>{label.confidence}</td>
                        </tr>
                      )
                    }
                    return null
                  })}
                </tbody>
              </table>
            )}
          </Dialog.Body>
        </Dialog>
      ) : null}
    </>
  )
}

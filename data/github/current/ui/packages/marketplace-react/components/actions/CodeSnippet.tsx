import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {Dialog, Heading, Link, Text, Stack} from '@primer/react'
import {repositoryPath} from '@github-ui/paths'
import styles from '../../marketplace.module.css'
import commonStyles from '@github-ui/marketplace-common/marketplace-common.module.css'
import {ListingLogo} from '../ListingLogo'
import type {Release, Repository} from '../../types'
import type {ActionListing} from '@github-ui/marketplace-common'

interface CodeSnippetProps {
  action: ActionListing
  repository: Repository
  isOpen: boolean
  onClose: () => void
  selectedRelease?: Release
  latestRelease: Release
}

export function CodeSnippet(props: CodeSnippetProps) {
  const {action, repository, isOpen, onClose, selectedRelease, latestRelease} = props
  const {externalUsesPathPrefix} = action

  const version = selectedRelease ? selectedRelease.tagName : latestRelease.tagName
  const usesValue = `${externalUsesPathPrefix}${version}`

  // This format ensures that the code snippet is correctly indented when copied
  const textToCopy = `- name: ${action.name}
  uses: ${usesValue}`

  return (
    <>
      {isOpen && (
        <Dialog
          onClose={onClose}
          title={
            <Stack direction="horizontal" align="center">
              <ListingLogo listing={action} additionalDivClasses={commonStyles['marketplace-logo--dialog']} />
              <div>
                <Heading as="h3" variant="small" className="lh-condensed">
                  {action.name}
                </Heading>
                {action.description && (
                  <Text as="p" size="medium" weight="normal" className="color-fg-muted m-0 lh-condensed">
                    {action.description}
                  </Text>
                )}
              </div>
            </Stack>
          }
        >
          <Heading as="h2" className="h6" data-testid="code-snippet-dialog">
            Installation
          </Heading>
          <p className="text-small color-fg-muted">
            Copy and paste the following snippet into your <span className="text-mono">.yml</span> file.
          </p>
          <div className="copyable-terminal mb-2">
            <div className="copyable-terminal-button">
              <CopyToClipboardButton textToCopy={textToCopy} ariaLabel={'Copy to clipboard'} />
            </div>
            <pre className={`${styles['copyable-code-snippet']}`}>
              <p>- name: {action.name}</p>
              <p>&nbsp;&nbsp;uses: {usesValue}</p>
            </pre>
          </div>
          {repository.owner && repository.name && (
            <Link href={repositoryPath({owner: repository.owner, repo: repository.name})} className="text-small">
              Learn more about this action in{' '}
              <strong>
                {repository.owner}/{repository.name}
              </strong>
            </Link>
          )}
        </Dialog>
      )}
    </>
  )
}

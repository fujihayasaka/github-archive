import {ActionList, Link} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {DesktopDownloadIcon, TerminalIcon} from '@primer/octicons-react'
import {CodeDropdownButton} from '@github-ui/code-dropdown-button'
import {CloneUrl} from '@github-ui/code-dropdown-button/components/LocalTab'
import type {Repository} from '@github-ui/current-repository'
import {useNavigate} from '@github-ui/use-navigate'
import {buildCodespacesPath} from '@github-ui/code-dropdown-button/components/CodespacesTab'

export interface PullRequestCodeButtonProps {
  codespacesEnabled: boolean
  copilotEnabled: boolean
  headBranch: string
  isEnterprise: boolean
  pullRequestNumber: number
  repository: Repository
}

export function PullRequestCodeButton({
  codespacesEnabled,
  copilotEnabled,
  headBranch,
  isEnterprise,
  pullRequestNumber,
  repository,
}: PullRequestCodeButtonProps) {
  const copilotTabProps = {repoOwner: repository.ownerLogin, repoName: repository.name, refName: headBranch}
  const codespacesPath = buildCodespacesPath(repository.id, headBranch)

  return (
    <CodeDropdownButton
      primary={false}
      size="small"
      isEnterprise={isEnterprise}
      showCodespacesTab={codespacesEnabled}
      codespacesPath={codespacesPath}
      showCopilotTab={copilotEnabled}
      copilotTabProps={copilotTabProps}
      localTab={<LocalTab pullNumber={pullRequestNumber} />}
    />
  )
}

interface LocalTabProps {
  pullNumber: number
}

function LocalTab(props: LocalTabProps) {
  const {pullNumber} = props
  const promptText = 'Checkout with GitHub CLI'
  const cloneText = `gh pr checkout ${pullNumber}`
  const navigate = useNavigate()

  return (
    <ActionList className="py-0">
      <ul>
        <li className="mt-2 px-3 py-2">
          <div className="d-flex flex-items-center mb-2">
            <Octicon className="mr-2" icon={TerminalIcon} />
            <p className="text-bold mb-0">{promptText}</p>
          </div>
          <CloneUrl
            buttonAriaLabel="Copy command to clipboard"
            inputId="checkout-with-gh-cli"
            inputLabel={`${promptText} command`}
            url={cloneText}
          />
          <p className="text-normal color-fg-muted">
            Work fast with our official CLI.{' '}
            <Link inline href="https://cli.github.com" target="_blank" aria-label="Learn more about the GitHub CLI">
              Learn more
            </Link>
          </p>
        </li>
      </ul>
      <ActionList.Divider />
      <ActionList.Item className="my-2" onSelect={() => navigate('https://desktop.github.com')}>
        <div className="d-flex flex-items-center">
          <Octicon className="mr-2" icon={DesktopDownloadIcon} />
          <p className="text-bold mb-0">Checkout with GitHub Desktop</p>
        </div>
      </ActionList.Item>
    </ActionList>
  )
}

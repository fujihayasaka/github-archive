import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {McpSettings} from '../components/McpSettings'
import type {CopilotSweAgentPayload} from '../types'
import {Label, Link, Stack, Text} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {PageHeading} from '../components/Ui'

export function RepoSettings() {
  const {access_warning_banner_content, mcpConfiguration, endpoint} = useRoutePayload<CopilotSweAgentPayload>()

  return (
    <div>
      <PageHeading
        name="Copilot coding agent"
        meta={
          <Label variant="success" className="ml-2">
            Preview
          </Label>
        }
      />
      {access_warning_banner_content && (
        <Banner variant="warning" title="No Copilot coding agent access" hideTitle className="mb-3">
          {access_warning_banner_content}
        </Banner>
      )}
      <Stack space="normal" data-hpc>
        <p>
          With Copilot coding agent, developers can delegate tasks to Copilot, freeing them to focus on the creative,
          complex, and high-impact work that matters most. Simply assign an issue to Copilot, wait for the agent to
          request review, then leave feedback on the pull request to iterate. To learn more, see the{' '}
          <Link href="https://gh.io/copilot-coding-agent-docs" inline>
            GitHub Docs
          </Link>
          .
        </p>
        <h3>Model Context Protocol (MCP)</h3>
        <p>
          The MCP is an open standard that defines how applications share context with large language models (LLMs). MCP
          provides a standardized way to connect AI models to different data sources and tools, enabling them to work
          together more effectively.
        </p>
        <p>
          You can use MCP to extend the capabilities of Copilot coding agent by connecting it to other tools and
          services. For information on how to write your JSON MCP configuration, see the{' '}
          <Link href="https://gh.io/copilot-coding-agent-mcp-docs" inline>
            GitHub Docs
          </Link>
          .
        </p>
      </Stack>
      <McpSettings endpoint={endpoint} initialValue={mcpConfiguration ?? '{ "mcpServers": {} }'} />
      <Text as="p" sx={{color: 'fg.muted', mt: 4}}>
        Use of Copilot coding agent is subject to the{' '}
        <Link inline href="https://docs.github.com/en/site-policy/github-terms/github-pre-release-license-terms">
          pre-release terms
        </Link>
        .
      </Text>
    </div>
  )
}

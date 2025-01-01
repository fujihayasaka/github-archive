import DOMPurify from 'dompurify'

import type {CopilotChatAgent} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import type {CopilotMarkdownExtension} from '../extension'

function linkifyAtMention(
  inputString: string,
  agents?: CopilotChatAgent[],
  fetchAgents?: () => Promise<CopilotChatAgent[]>,
) {
  // Use regex to find a substring beginning with '@' at the beginning of the string.
  const atMentions = inputString.match(/^@\S+/g)

  // If there is not an '@' mentions, return the original string.
  if (!atMentions || atMentions.length === 0) {
    return inputString
  }

  if (!agents) {
    // fetch the agents, but don't hold up showing the message.
    void fetchAgents?.()
    return inputString
  }

  // There should only be a single mention.
  const mention = atMentions[0]

  // If the agents array contains the mention without the '@'
  const mentionSlug = mention.substring(1)
  const matchingAgent = agents.find(agent => agent.slug === mentionSlug)
  if (matchingAgent) {
    // Replace the mention in the original string with an HTML anchor tag
    const sanitizedMention = DOMPurify.sanitize(mention)
    inputString = inputString.replace(
      mention,
      // eslint-disable-next-line github/unescaped-html-literal
      `<a href="${matchingAgent.integrationUrl}" data-hovercard-url="/integrations/${mentionSlug}/hovercard" class="bgColor-accent-muted">${sanitizedMention}</a>`,
    )
  }
  return inputString
}

interface AtMentionsExtensionOptions {
  agents?: CopilotChatAgent[]
  fetchAgents?: () => Promise<CopilotChatAgent[]>
}

export default function atMentionsExtension({
  agents,
  fetchAgents,
}: AtMentionsExtensionOptions): CopilotMarkdownExtension {
  return {
    marked: [
      {
        hooks: {
          preprocess(markdown) {
            return linkifyAtMention(markdown, agents, fetchAgents)
          },
          postprocess(html) {
            return html
          },
        },
      },
    ],
    sanitizer: {
      allowedClassNames: ['bgColor-accent-muted'],
    },
  }
}

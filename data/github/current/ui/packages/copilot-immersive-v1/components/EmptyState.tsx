import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/utils/CopilotChatManagerContext'
import {sendEvent} from '@github-ui/hydro-analytics'
import {BugIcon, CodeIcon, GitPullRequestIcon, IssueOpenedIcon, QuestionIcon, RocketIcon} from '@primer/octicons-react'
import {Link} from '@primer/react'

import {CopilotAnimation} from './CopilotAnimation'
import classes from './EmptyState.module.css'
import {SuggestionCard} from './SuggestionCard'

// TODO: Improve with more suggestions once we have setting context back
const suggestions = [
  {
    id: 0,
    raw: 'Open issues in facebook/react',
    title: (
      <>
        Open issues in <span className={classes.replaceValue}>facebook/react</span>
      </>
    ),
    icon: <IssueOpenedIcon />,
    color: 'var(--display-green-fgColor)',
  },
  {
    id: 1,
    raw: 'Create a profile README for $$USERNAME$$',
    title: 'Create a profile README for me',
    icon: <RocketIcon />,
    color: 'var(--display-purple-fgColor)',
  },
  {
    id: 2,
    raw: 'Tooltip libraries in JavaScript',
    title: (
      <>
        Tooltip libraries in <span className={classes.replaceValue}>JavaScript</span>
      </>
    ),
    icon: <CodeIcon />,
    color: 'var(--display-gray-fgColor)',
  },
  {
    id: 3,
    raw: 'What is a hash table?',
    title: 'What is a hash table?',
    icon: <QuestionIcon />,
    color: 'var(--display-yellow-fgColor)',
  },
  {
    id: 4,
    raw: 'Recent bugs in primer/react',
    title: (
      <>
        Recent bugs in <span className={classes.replaceValue}>primer/react</span>
      </>
    ),
    icon: <BugIcon />,
    color: 'var(--display-gray-fgColor)',
  },
  {
    id: 5,
    raw: 'My open pull requests',
    title: 'My open pull requests',
    icon: <GitPullRequestIcon />,
    color: 'var(--fgColor-open)',
  },
]

export function EmptyState({showSuggestions}: {showSuggestions: boolean}) {
  const manager = useChatManager()
  const state = useChatState()

  const currentThread = manager.getSelectedThread(state)

  return (
    <div className={classes.container}>
      <CopilotAnimation />
      {showSuggestions && (
        <div>
          <h1 className="sr-only">Copilot Chat</h1>
          <h2 className="sr-only">Sample prompts to try</h2>
          <ul className={`${classes.suggestions} list-style-none`}>
            {suggestions.map(suggestion => (
              <li key={suggestion.id} className={classes.suggestionButton}>
                <SuggestionCard
                  key={suggestion.id}
                  title={suggestion.title}
                  icon={suggestion.icon}
                  color={suggestion.color}
                  onClick={() => {
                    const thread = state.messages.length === 0 ? currentThread : manager.getSelectedThread(state)
                    void manager.sendChatMessage(
                      thread,
                      suggestion.raw.replaceAll('$$USERNAME$$', state.currentUserLogin),
                      state.currentReferences,
                      state.currentTopic,
                      state.context,
                    )
                    sendEvent('dotcom_chat.activate', {
                      target: 'EMPTY_STATE_SUGGESTION_CARD',
                      topic: state.currentTopic?.name,
                      mode: 'immersive',
                    })
                  }}
                />
              </li>
            ))}
          </ul>
        </div>
      )}
      <p className={classes.legalText}>
        <Link
          href="https://docs.github.com/en/copilot/responsible-use-of-github-copilot-features/responsible-use-of-github-copilot-chat-in-githubcom"
          inline
          muted
          onClick={() =>
            sendEvent('dotcom_chat.activate', {
              target: 'EMPTY_STATE_LEGAL_LINK',
              mode: 'immersive',
            })
          }
        >
          Copilot
        </Link>{' '}
        uses AI. Check for mistakes.
      </p>
    </div>
  )
}

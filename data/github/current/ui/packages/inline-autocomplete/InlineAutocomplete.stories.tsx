import {GitHubAvatar as Avatar} from '@github-ui/github-avatar'
import {ActionList, type ActionListItemProps, FormControl, Textarea, TextInput} from '@primer/react'
import type {Meta} from '@storybook/react'
import {useState} from 'react'

import {InlineAutocomplete} from '.'
import styles from './InlineAutocomplete.stories.module.css'
import type {ShowSuggestionsEvent, Suggestion, Suggestions, Trigger} from './types'
import {getSuggestionValue} from './utils'

export default {
  title: 'Recipes/InlineAutocomplete',
  component: InlineAutocomplete,
  parameters: {
    controls: {sort: 'alpha'},
  },
  args: {
    loading: false,
    tabInserts: false,
  },
  argTypes: {
    loading: {
      name: 'Loading',
      control: {
        type: 'boolean',
      },
    },
    tabInserts: {
      name: '`Tab` Key Inserts Suggestions',
      control: {
        type: 'boolean',
      },
    },
  },
} as Meta

interface User {
  login: string
  name: string
  avatar: string
  type: 'user' | 'organization'
}

const sampleUsers: User[] = [
  {login: 'monalisa', name: 'Monalisa Octocat', avatar: 'https://avatars.githubusercontent.com/github', type: 'user'},
  {login: 'primer', name: 'Primer', avatar: 'https://avatars.githubusercontent.com/primer', type: 'organization'},
  {login: 'github', name: 'GitHub', avatar: 'https://avatars.githubusercontent.com/github', type: 'organization'},
]

const filteredUsers = (query: string) =>
  sampleUsers.filter(
    user =>
      user.login.toLowerCase().includes(query.toLowerCase()) || user.name.toLowerCase().includes(query.toLowerCase()),
  )

export const Default = ({loading, tabInserts}: ArgProps) => {
  const [suggestions, setSuggestions] = useState<Suggestions | null>(null)

  const onShowSuggestions = (event: ShowSuggestionsEvent) => {
    if (loading) {
      setSuggestions('loading')
      return
    }

    setSuggestions(filteredUsers(event.query).map(user => user.login))
  }

  return (
    <FormControl>
      <FormControl.Label>Inline Autocomplete Demo</FormControl.Label>
      <FormControl.Caption>Try typing &apos;@&apos; to show user suggestions.</FormControl.Caption>
      <InlineAutocomplete
        triggers={[{triggerChar: '@'}]}
        suggestions={suggestions}
        onShowSuggestions={onShowSuggestions}
        onHideSuggestions={() => setSuggestions(null)}
        tabInsertsSuggestions={tabInserts}
      >
        <Textarea />
      </InlineAutocomplete>
    </FormControl>
  )
}

type ArgProps = {
  loading: boolean
  tabInserts: boolean
}

export const Playground = ({loading, tabInserts}: ArgProps) => {
  const [suggestions, setSuggestions] = useState<Suggestions | null>(null)

  const onShowSuggestions = (event: ShowSuggestionsEvent) => {
    if (loading) {
      setSuggestions('loading')
      return
    }

    setSuggestions(filteredUsers(event.query).map(user => user.login))
  }
  return (
    <FormControl>
      <FormControl.Label>Inline Autocomplete Playground</FormControl.Label>
      <FormControl.Caption>Try typing &apos;@&apos; to show user suggestions.</FormControl.Caption>
      <InlineAutocomplete
        triggers={[{triggerChar: '@'}]}
        suggestions={suggestions}
        onShowSuggestions={onShowSuggestions}
        onHideSuggestions={() => setSuggestions(null)}
        tabInsertsSuggestions={tabInserts}
      >
        <Textarea />
      </InlineAutocomplete>
    </FormControl>
  )
}

export const SingleLine = ({loading, tabInserts}: ArgProps) => {
  const [suggestions, setSuggestions] = useState<Suggestions | null>(null)

  const onShowSuggestions = (event: ShowSuggestionsEvent) => {
    if (loading) {
      setSuggestions('loading')
      return
    }

    setSuggestions(filteredUsers(event.query).map(user => user.login))
  }

  return (
    <FormControl>
      <FormControl.Label>Inline Autocomplete Demo</FormControl.Label>
      <FormControl.Caption>Try typing &apos;@&apos; to show user suggestions.</FormControl.Caption>
      <InlineAutocomplete
        triggers={[{triggerChar: '@'}]}
        suggestions={suggestions}
        onShowSuggestions={onShowSuggestions}
        onHideSuggestions={() => setSuggestions(null)}
        tabInsertsSuggestions={tabInserts}
      >
        <TextInput className={styles.TextInput_0} />
      </InlineAutocomplete>
    </FormControl>
  )
}

export const OnSelectSuggestion = ({loading, tabInserts}: ArgProps) => {
  const [suggestions, setSuggestions] = useState<Suggestions | null>(null)

  const onShowSuggestions = (event: ShowSuggestionsEvent) => {
    if (loading) {
      setSuggestions('loading')
      return
    }

    setSuggestions(filteredUsers(event.query).map(user => user.login))
  }

  return (
    <FormControl>
      <FormControl.Label>Inline Autocomplete Demo</FormControl.Label>
      <FormControl.Caption>Try typing &apos;@&apos; to show user suggestions.</FormControl.Caption>
      <InlineAutocomplete
        triggers={[{triggerChar: '@'}]}
        onSelectSuggestion={suggestion => window.alert(`Selected ${suggestion.suggestion as string}`)}
        suggestions={suggestions}
        onShowSuggestions={onShowSuggestions}
        onHideSuggestions={() => setSuggestions(null)}
        tabInsertsSuggestions={tabInserts}
      >
        <TextInput className={styles.TextInput_0} />
      </InlineAutocomplete>
    </FormControl>
  )
}

const UserSuggestion = ({user, ...props}: {user: User} & ActionListItemProps) => (
  <ActionList.Item {...props}>
    <ActionList.LeadingVisual>
      <Avatar src={user.avatar} square={user.type === 'organization'} />
    </ActionList.LeadingVisual>
    {user.name} <ActionList.Description truncate>{user.login}</ActionList.Description>
  </ActionList.Item>
)

export const CustomRendering = ({loading, tabInserts}: ArgProps) => {
  const [suggestions, setSuggestions] = useState<Suggestions | null>(null)

  const onShowSuggestions = (event: ShowSuggestionsEvent) => {
    if (loading) {
      setSuggestions('loading')
      return
    }

    setSuggestions(
      filteredUsers(event.query).map(user => ({
        value: user.login,
        render: props => <UserSuggestion user={user} {...props} />,
      })),
    )
  }

  const onHideSuggestions = () => setSuggestions(null)

  return (
    <FormControl>
      <FormControl.Label>Inline Autocomplete Demo</FormControl.Label>
      <FormControl.Caption>Try typing &apos;@&apos; to show user suggestions.</FormControl.Caption>
      <InlineAutocomplete
        triggers={[{triggerChar: '@'}]}
        suggestions={suggestions}
        onShowSuggestions={onShowSuggestions}
        onHideSuggestions={onHideSuggestions}
        tabInsertsSuggestions={tabInserts}
      >
        <Textarea />
      </InlineAutocomplete>
    </FormControl>
  )
}

export const AbovePositioning = ({loading, tabInserts}: ArgProps) => {
  const [suggestions, setSuggestions] = useState<Suggestions | null>(null)

  const onShowSuggestions = (event: ShowSuggestionsEvent) => {
    if (loading) {
      setSuggestions('loading')
      return
    }

    setSuggestions(
      filteredUsers(event.query).map(user => ({
        value: user.login,
        render: props => <UserSuggestion user={user} {...props} />,
      })),
    )
  }

  const onHideSuggestions = () => setSuggestions(null)

  return (
    <FormControl className={styles.FormControl_0}>
      <FormControl.Label>Inline Autocomplete Demo</FormControl.Label>
      <FormControl.Caption>Try typing &apos;@&apos; to show user suggestions.</FormControl.Caption>
      <InlineAutocomplete
        triggers={[{triggerChar: '@'}]}
        suggestions={suggestions}
        onShowSuggestions={onShowSuggestions}
        onHideSuggestions={onHideSuggestions}
        suggestionsPlacement="above"
        tabInsertsSuggestions={tabInserts}
      >
        <Textarea className={styles.Textarea_0} />
      </InlineAutocomplete>
    </FormControl>
  )
}

export const AutoPositioning = ({loading, tabInserts}: ArgProps) => {
  const [suggestions, setSuggestions] = useState<Suggestions | null>(null)

  const onShowSuggestions = (event: ShowSuggestionsEvent) => {
    if (loading) {
      setSuggestions('loading')
      return
    }

    setSuggestions(
      filteredUsers(event.query).map(user => ({
        value: user.login,
        render: props => <UserSuggestion user={user} {...props} />,
      })),
    )
  }

  const onHideSuggestions = () => setSuggestions(null)

  return (
    <FormControl className={styles.FormControl_0}>
      <FormControl.Label>Inline Autocomplete Demo</FormControl.Label>
      <FormControl.Caption>Try typing &apos;@&apos; to show user suggestions.</FormControl.Caption>
      <InlineAutocomplete
        triggers={[{triggerChar: '@'}]}
        suggestions={suggestions}
        onShowSuggestions={onShowSuggestions}
        onHideSuggestions={onHideSuggestions}
        tabInsertsSuggestions={tabInserts}
      >
        <Textarea className={styles.Textarea_0} />
      </InlineAutocomplete>
    </FormControl>
  )
}

export const MultiCharTrigger = ({loading, tabInserts}: ArgProps) => {
  const [suggestions, setSuggestions] = useState<Suggestions | null>(null)

  const onShowSuggestions = (event: ShowSuggestionsEvent) => {
    if (loading) {
      setSuggestions('loading')
      return
    }

    setSuggestions(filteredUsers(event.query).map(user => `@${user.login}`))
  }

  return (
    <FormControl>
      <FormControl.Label>Inline Autocomplete Demo</FormControl.Label>
      <FormControl.Caption>Try typing &apos;@u&apos; to show user suggestions.</FormControl.Caption>
      <InlineAutocomplete
        triggers={[{triggerChar: '@u', keepTriggerCharOnCommit: false}]}
        suggestions={suggestions}
        onShowSuggestions={onShowSuggestions}
        onHideSuggestions={() => setSuggestions(null)}
        tabInsertsSuggestions={tabInserts}
      >
        <Textarea />
      </InlineAutocomplete>
    </FormControl>
  )
}

interface Category {
  char: string
  name: string
  suggestions: Suggestion[]
}

const categories: Category[] = [
  {char: 'e', name: 'Extension', suggestions: ['mermaid', 'blackbeard']},
  {char: 'r', name: 'Repository', suggestions: ['github/github', 'primer/react', 'github/copilot-api']},
  {char: 'f', name: 'File', suggestions: ['example.text', 'index.html', 'readme.md', 'image.png']},
  {
    char: 'k',
    name: 'Knowledge base',
    suggestions: [
      {render: p => <ActionList.Item {...p}>GitHub Docs</ActionList.Item>, value: 'gh-docs'},
      {render: p => <ActionList.Item {...p}>Primer Docs</ActionList.Item>, value: 'primer-docs'},
      {render: p => <ActionList.Item {...p}>The Whole Internet</ActionList.Item>, value: 'internet'},
    ],
  },
]

const triggers: Trigger[] = [
  {triggerChar: '@', keepTriggerCharOnCommit: true, insertSpaceOnCommit: false},
  ...categories.map(c => ({triggerChar: `@${c.char}`, keepTriggerCharOnCommit: false})),
]

const categoryTriggerSuggestions: Suggestion[] = categories.map(c => ({
  value: c.char,
  render: p => (
    <ActionList.Item {...p}>
      {c.name} <ActionList.Description>@{c.char}</ActionList.Description>
    </ActionList.Item>
  ),
}))

const categorySuggestionsByChar = new Map(categories.map(c => [`@${c.char}`, c.suggestions]))

export const MultiStep = ({loading, tabInserts}: ArgProps) => {
  const [suggestions, setSuggestions] = useState<Suggestions | null>(null)

  const onShowSuggestions = (event: ShowSuggestionsEvent) => {
    if (loading) {
      setSuggestions('loading')
      return
    }
    if (event.trigger.triggerChar === '@') setSuggestions(categoryTriggerSuggestions)
    else
      setSuggestions(
        categorySuggestionsByChar
          .get(event.trigger.triggerChar)
          ?.filter(s => getSuggestionValue(s).startsWith(event.query)) ?? null,
      )
  }

  return (
    <FormControl>
      <FormControl.Label>Inline Autocomplete Demo</FormControl.Label>
      <FormControl.Caption>Try typing &apos;@&apos; to show categories.</FormControl.Caption>
      <InlineAutocomplete
        triggers={triggers}
        suggestions={suggestions}
        onShowSuggestions={onShowSuggestions}
        onHideSuggestions={() => setSuggestions(null)}
        tabInsertsSuggestions={tabInserts}
      >
        <Textarea autoComplete="off" />
      </InlineAutocomplete>
    </FormControl>
  )
}

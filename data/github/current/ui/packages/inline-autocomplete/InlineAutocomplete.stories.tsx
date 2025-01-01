import {GitHubAvatar as Avatar} from '@github-ui/github-avatar'
import {ActionList, type ActionListItemProps, FormControl, Textarea, TextInput} from '@primer/react'
import type {Meta} from '@storybook/react'
import {useState} from 'react'

import {InlineAutocomplete} from '.'
import styles from './InlineAutocomplete.stories.module.css'
import type {ShowSuggestionsEvent, Suggestions} from './types'

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

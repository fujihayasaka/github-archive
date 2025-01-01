# State Management for React Front End

## Status
Proposed - 2023-10-05

## Context

There are various options for state management with React. It is an important to consider the options before starting development as it can greatly affect the flow of data and the patterns used in developing components. The following options for state managment will be considered at this time:

- React built-in state management (hooks/context)
- Relay
- Valtio
- Recoil
- Mobx
- TanStack Query
- Custom implementation of observables

## React Built-in State Management

State management can be accomplished with React's build-in hooks and context. Hooks are used to manage local state, and context is used to manage global state.

<details>

<summary>Example</summary>

```ts
import { createContext, useState, useContext, useMemo } from 'react';

// context
const UserContext = createContext({
  userName: '',
  setUserName: () => {},
});

// provider
function Application() {
  const [userName, setUserName] = useState('John Smith');
  const value = useMemo(
    () => ({ userName, setUserName }), 
    [userName]
  );
  
  return (
    <UserContext.Provider value={value}>
      {useMemo(() => (
        <>
          <UserNameInput />
          <UserInfo />
        </>
      ), [])}
    </UserContext.Provider>
  );
}

// components
function UserNameInput() {
  const { userName, setUserName } = useContext(UserContext);
  const changeHandler = event => setUserName(event.target.value);

  return (
    <input
      type="text"
      value={userName}
      onChange={changeHandler}
    />
  );
}

function UserInfo() {
  const { userName } = useContext(UserContext);
  return <span>{userName}</span>;
}
```

</details>

### Pros

- Built-in solution for React, so it is very standard
- Works really well for small/simple components

### Cons

- Can cause performance issues as any changes to context cause all components that useContext to rerender.
- Can be hard to scale and maintain for a large-scale app
- Encourages blurring lines between view (component) and controller/model which adds complexity to understanding the code.
- Can become very complex in more complicated components/contexts where multiple properties need to be tracked
- Can lead to lots of boilerplate code
- Components that want to access context must be wrapped in a provider
- Can't subscribe to changes in a subpart of the context (all or nothing)

## Relay

[Relay](https://relay.dev/) is the paved path at Github, and under most circumstances it would be the clear choice. Unfortunately it requires GraphQL, and there is no current plan to implement GraphQL for the Actions Metrics back-end leaving React Relay unavailable. As this choice is unavailable it will not be discussed further in this document.

## Valtio

[Valtio](https://github.com/pmndrs/valtio) uses the proxy pattern to make managing state simple by wrapping the state in a proxy, and then using a pub/sub system instead of React context ([in-depth details here](https://marmelab.com/blog/2022/06/23/proxy-state-with-valtio.html)). State is created with the `proxy`, and then accessed with then accessed through a `snapshot`. When accessed through the `snapshot` only changes in the properties actually used within the component trigger rerenders.

<details>

<summary>Example</summary>

```ts
import { proxy, useSnapshot } from 'valtio'

const state = proxy({ count: 0, text: 'hello' })

setInterval(() => {
  ++state.count
}, 1000)

// This will re-render on `state.count` change but not on `state.text` change
function Counter() {
  const snap = useSnapshot(state)
  return (
    <div>
      {snap.count}
      <button onClick={() => ++state.count}>+1</button>
    </div>
  )
}
```

</details>

### Pros

- Examples make it seem very easy to use and adaptable to different patterns
- Easier to manage state and better performance, as only changes to the accessed properties trigger rerenders
- Useful utils for more complex scenarios such as derived states

### Cons

- No one on team is familiar with it, but it has some usage at GH
- Some of the Valtio "magic" might make debugging a little more complicated if we run into issues

## Recoil

[Recoil](https://recoiljs.org/) lets you create a data-flow graph that flows from `atoms` (shared state) through `selectors` (pure functions) and down into your React components. Atoms are units of state that components can subscribe to. Selectors transform this state either synchronously or asynchronously.

<details>

<summary>Example</summary>

```ts
const textState = atom({
  key: 'textState', // unique ID (with respect to other atoms/selectors)
  default: '', // default value (aka initial value)
});

function CharacterCounter() {
  return (
    <div>
      <TextInput />
      <CharacterCount />
    </div>
  );
}

function TextInput() {
  const [text, setText] = useRecoilState(textState);

  const onChange = (event) => {
    setText(event.target.value);
  };

  return (
    <div>
      <input type="text" value={text} onChange={onChange} />
      <br />
      Echo: {text}
    </div>
  );
}

const charCountState = selector({
  key: 'charCountState', // unique ID (with respect to other atoms/selectors)
  get: ({get}) => {
    const text = get(textState);

    return text.length;
  },
});

function CharacterCount() {
  const count = useRecoilValue(charCountState);

  return <>Character Count: {count}</>;
}
```

</details>

### Pros

- Developed by Facebook (large and trustworthy source)
- Very "Reacty" patterns and practices
- Work well with React hooks

### Cons

- No one on team is familiar with it, and it is not used anywhere else in GH
- Very large and complex library for state management, and learning to use it correctly would be a task in itself

## MobX

[MobX](https://mobx.js.org/README.html) is a state management pattern that follows the observable pattern. It "magically" tracks what components need to React to different state by creating a dependency-graph behind the scenes.

<details>

<summary>Example</summary>

```ts
import React from "react"
import ReactDOM from "react-dom"
import { makeAutoObservable } from "mobx"
import { observer } from "mobx-react-lite"

class Timer {
    secondsPassed = 0

    constructor() {
        makeAutoObservable(this)
    }

    increaseTimer() {
        this.secondsPassed += 1
    }
}

const myTimer = new Timer()

// A function component wrapped with `observer` will react
// to any future change in an observable it used before.
const TimerView = observer(({ timer }) => <span>Seconds passed: {timer.secondsPassed}</span>)

ReactDOM.render(<TimerView timer={myTimer} />, document.body)

setInterval(() => {
    myTimer.increaseTimer()
}, 1000)
```

</details>

### Pros

- Makes it easier to manage state through observables
- Well-known library for state management in React
- No boilerplate code

### Cons

- Some team familiarity, and while it is used by the Memex team they are currently moving away from it
- Documentation can be a little poor/confusing
- The "magic" can make debugging difficult, and it can be easy to miss small mistakes

## TanStack Query

[TanStack Query](https://tanstack.com/query/latest/docs/react/overview) is a data-fetching library for web applications, but in more technical terms, it makes fetching, caching, synchronizing and updating server state in web applications much easier. It is not really a state management library, although it does have some built-in state management for queries.

<details>

<summary>Example</summary>

```ts
import {
  QueryClient,
  QueryClientProvider,
  useQuery,
} from '@tanstack/react-query'

const queryClient = new QueryClient()

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <Example />
    </QueryClientProvider>
  )
}

function Example() {
  const { isLoading, error, data } = useQuery({
    queryKey: ['repoData'],
    queryFn: () =>
      fetch('https://api.github.com/repos/TanStack/query').then(
        (res) => res.json(),
      ),
  })

  if (isLoading) return 'Loading...'

  if (error) return 'An error has occurred: ' + error.message

  return (
    <div>
      <h1>{data.name}</h1>
      <p>{data.description}</p>
      <strong>👀 {data.subscribers_count}</strong>{' '}
      <strong>✨ {data.stargazers_count}</strong>{' '}
      <strong>🍴 {data.forks_count}</strong>
    </div>
  )
}
```
</details>

### Pros

- Greatly simplifies data-fetching.
- Some teams are using it at GH

### Cons

- Overkill for our current needs - we have very simple query needs as of now.
- Would likely still want another solution for handling client-side state management.

## Custom Implementation of Observables

Observables are pretty straightforward to implement, and it would be easy for the team to do the same ([see example here](https://medium.com/betomorrow/replacing-redux-with-observables-and-react-hooks-acdbbaf5ba80)). This would give total control over performance, and allow for a similar flow to MobX, but with a more simplified and stripped-down implementation made to suit our needs. This would likely not be a true custom implementation, but a fork of a very minor/lightweight implementation such as [micro-observables](https://github.com/BeTomorrow/micro-observables) or something like the earlier linked [example](https://medium.com/betomorrow/replacing-redux-with-observables-and-react-hooks-acdbbaf5ba80).

<details>

<summary>Example</summary>

```ts
import React from "react"
import ReactDOM from "react-dom"
import { Observable, Observer } from "./observables"
import { MetricsData } from "./models"

const tableData = new Observable<MetricsData[]>

verifiedFetch(tableApiPath, {method: 'GET'})
  .then(data => tableData.value = data);

function MetricsTable() {
  return (
    <table>
      <Observer rows={tableData}>
        {(rows) => { //observer watches tableData for changes, and dereferences it so can access underlying data directly
          return rows.map(row => <MetricRow data={row}/>); 
        }}
      </Observer>
    </table>
  );
}
```

</details>

### Pros

- Gives complete control over performance
- Solution could be more simple and streamlined to fit our needs
- Observable pattern would make state management very simple: Data is stored in observable objects, and components subcribe to changes by wrapping UI that needs to rerender in an observer

### Cons

- Using own implementation, no matter how simple, means additional development and documentation
- Less "Reacty" pattern

## Decision

Use custom observable implementation for complex state management and React built-in hooks for simpler more encapsulated scenarios. We will not be using TanStack Query at this time, but we may adopt it at some point in the future if the querying data becomes more complex.

### Reasoning

After evaluating the different solutions, the two standouts for overall simplicity are Valtio and the custom observable implementation. Even though Valtio may suit our needs, the decision is ultimately a custom lightweight observable implemntation. This would give us full control without being dependent on a package that, while well regarded, has little consumption within GH.

There are some situations where this may be overkill, and we will still have access to React's built-in hooks so we will still use those when appropriate.

Additionally, while TanStack query is not needed at the moment, we will keep it in mind. If data-fetching starts to become more complex we will revisit it as a possible solution working in conjunction with the client-side state management since Relay is not possible without GraphQL.
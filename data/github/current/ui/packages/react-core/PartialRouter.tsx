import {useLayoutEffect} from '@github-ui/use-layout-effect'
import type {BrowserHistory, MemoryHistory} from '@remix-run/router'
import {useState} from 'react'
import {Router} from 'react-router-dom'

type Props = {
  children: React.ReactNode
  history: BrowserHistory | MemoryHistory
}

export function PartialRouter({children, history}: Props) {
  const [state, setState] = useState({
    location: history.location,
  })

  useLayoutEffect(() => history.listen(setState), [history])

  return (
    <Router location={state.location} navigator={history} future={{v7_relativeSplatPath: true}}>
      {children}
    </Router>
  )
}

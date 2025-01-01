import {useState} from 'react'
import type {BrowserHistory, MemoryHistory} from '@remix-run/router'
import {Router} from 'react-router-dom'
import {useLayoutEffect} from '@github-ui/use-layout-effect'

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

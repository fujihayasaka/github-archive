import {useLocation, useNavigationType} from 'react-router-dom'

import {useNavigationFocus} from '../use-navigation-focus'

export function NavigationFocusListener() {
  const location = useLocation()
  const navigationAction = useNavigationType()
  // The first argument to useNavigationFocus is a boolean that indicates that we might be loading.
  // For example, if the location changes, but there's still XHR fetches to be made. Those remaining
  // XHR (data loaders), when they resolve, can change the shape of the page and we don't want to
  // do the navigation focus until that's settled.
  // But in our data router framework, when you soft-nav, the location won't change until the loaders
  // resolve. So you can't be going to a new page and still be loading.
  // This is why we don't need to use `useNavigation()` and its `navigation.state==='loading'` here.
  useNavigationFocus(false, location, navigationAction)

  return null
}

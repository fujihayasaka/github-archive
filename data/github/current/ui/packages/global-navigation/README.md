# Updating global navigation client-side

If you need to update the global navigation breadcrumbs client-side (including from React apps and components), install this package in your project and simply make use of one of our exported functions:

```js
import {
  pushNavigationBreadcrumb,
  popNavigationBreadcrumb,
  replaceNavigationBreadcrumbs,
  replaceCurrentNavigationBreadcrumb,
  renameCurrentNavigationBreadcrumb,
} from '@github-ui/global-navigation'

// You will likely want to do this inside of a useEffect or other hook when working in React
useEffect(() => {
  // add a new breadcrumb to the global nav
  pushNavigationBreadcrumb({
    label: 'My new crumb!',
    href: '#',
  })
  
  // remove the most recent navigation crumb
  popNavigationBreadcrumb()
  
  // replace all of the crumbs in the nav
  const crumbs = [
    {label: 'Here', href: '#'},
    {label: 'are', href: '#'},
    {label: 'new', href: '#'},
    {label: 'crumbs', href: '#'},
  ]
  
  replaceNavigationBreadcrumbs(crumbs)
  
  // replace only the current page's crumb
  replaceCurrentNavigationBreadcrumb({
    label: 'Dashboard',
    href: '/',
  })
  
  // rename the current page's crumb
  renameCurrentNavigationBreadcrumb('Fish sticks')
}, [])
```

All crumb objects provided to these functions require a `label` property, and `href` is optional.

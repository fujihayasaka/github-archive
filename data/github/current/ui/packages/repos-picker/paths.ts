import type {PickerScope} from './types'

export const reposPickerDefinitionsPath = (scope: PickerScope) =>
  `/repositories/picker/definitions?${getOwnerFromScope(scope)}`

interface ReposPickerRepositoriesPathProps {
  scope: PickerScope
  query?: string
}

export const reposPickerRepositoriesPath = ({scope, query}: ReposPickerRepositoriesPathProps) => {
  const params = getParamsFromScope(scope)

  if (query) {
    params.push(`q=${encodeURIComponent(query)}`)
  }

  return `/repositories/picker/search?${params.join('&')}`
}

export const reposPickerRepositoriesCountPath = ({scope, query}: Required<ReposPickerRepositoriesPathProps>) => {
  const params = [...getParamsFromScope(scope), `q=${encodeURIComponent(query)}`]

  return `/repositories/picker/count?${params.join('&')}`
}

function getParamsFromScope(scope: PickerScope) {
  const params = [getOwnerFromScope(scope)]

  if (scope.visibility) {
    params.push(`visibility=${encodeURIComponent(scope.visibility.join(','))}`)
  }

  return params.filter(Boolean)
}

function getOwnerFromScope(scope: PickerScope) {
  if (scope.type === 'enterprise') {
    return `enterprise=${encodeURIComponent(scope.slug)}`
  }

  if (scope.type === 'organization' || scope.type === 'user') {
    return `owner=${encodeURIComponent(scope.slug)}`
  }

  return ''
}

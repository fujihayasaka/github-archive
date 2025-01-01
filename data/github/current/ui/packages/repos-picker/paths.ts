export const reposPickerDefinitionsPath = ({orgLogin}: {orgLogin: string}) =>
  `/repos-picker/definitions?org=${encodeURIComponent(orgLogin)}`

interface ReposPickerRepositoriesPathProps {
  orgLogin?: string
  query?: string
}

export const reposPickerRepositoriesPath = ({orgLogin, query}: ReposPickerRepositoriesPathProps) => {
  const params = []

  if (orgLogin) {
    params.push(`org=${encodeURIComponent(orgLogin)}`)
  }

  if (query) {
    params.push(`q=${encodeURIComponent(query)}`)
  }

  const queryString = params.length ? `?${params.join('&')}` : ''
  return `/repos-picker/repositories${queryString}`
}

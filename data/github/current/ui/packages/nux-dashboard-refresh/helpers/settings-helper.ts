import {verifiedFetch} from '@github-ui/verified-fetch'

export const updateSetting = async (setting: string, value: boolean) => {
  const data = new FormData()
  data.set(setting, value.toString())

  await verifiedFetch('/dashboard/preferences', {
    method: 'PUT',
    body: data,
  })
}

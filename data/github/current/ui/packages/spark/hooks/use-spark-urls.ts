import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useCallback} from 'react'

export const useSparkUrls = () => {
  const shouldUseUpdatedUrls = useFeatureFlag('spark_workbench_updated_urls')

  const showUrl = useCallback(
    (identifier: string, owner?: string, friendlyName?: string) => {
      if (shouldUseUpdatedUrls && friendlyName && owner) {
        return `/spark/${owner}/${friendlyName}`
      }
      if (shouldUseUpdatedUrls && owner) {
        return `/spark/${owner}/${identifier}`
      }

      return `/copilot/spark/${identifier}`
    },
    [shouldUseUpdatedUrls],
  )

  return {
    showUrl,
  }
}

import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {registerReactPartial} from '@github-ui/react-core/register-partial'
import {useEffect} from 'react'
import {DiffHeaderAskCopilotButton} from '../react/DiffHeaderAskCopilotButton'
import {InjectedDiffEntries} from '../react/InjectedDiffEntries'
import {ErrorAskCopilotButton, LoadingAskCopilotButton} from '../shared/DiffHeaderAskCopilotButton'
import {
  GetDiffEntryDataForbiddenError,
  useGetDiffEntryData,
  type useGetDiffEntryDataProps,
} from '../shared/use-get-diff-entry-data'

export const CopilotDiffChatDataLoaderPartial: React.FC<useGetDiffEntryDataProps> = props => {
  const {entriesData, loading, error} = useGetDiffEntryData(props)

  // ideally we check for copilot chat access before rendering these components, but check just in case
  if (error instanceof GetDiffEntryDataForbiddenError) return null

  if (error) return <ErrorAskCopilotButton />
  if (loading) return <LoadingAskCopilotButton />

  return (
    <>
      <DiffHeaderAskCopilotButton entriesData={entriesData} />
      <InjectedDiffEntries entriesData={entriesData} />
    </>
  )
}

/**
 * One partial for each Rails diff view inserts React components for each file, minimizing the performance cost of
 * instantiating many partials. In other words:
 *
 * > _One Partial to rule them all, One Partial to find them, One Partial to bring them all and in the React bind them._
 */
const CopilotDiffChatWrapperPartial: React.FC<useGetDiffEntryDataProps> = props => {
  // add a class name when rendering so that we can know when to change some styles downstream
  useEffect(() => {
    document.querySelector('diff-layout')?.classList.add('copilot-chat-enabled')
  }, [])

  return (
    <ErrorBoundary fallback={<ErrorAskCopilotButton />}>
      <CopilotDiffChatDataLoaderPartial {...props} />
    </ErrorBoundary>
  )
}

registerReactPartial('copilot-code-chat', {
  Component: CopilotDiffChatWrapperPartial,
})

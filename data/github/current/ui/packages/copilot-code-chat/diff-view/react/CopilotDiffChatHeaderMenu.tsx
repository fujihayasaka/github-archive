import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {ErrorAskCopilotButton, LoadingAskCopilotButton} from '../shared/DiffHeaderAskCopilotButton'
import {
  GetDiffEntryDataForbiddenError,
  useGetDiffEntryData,
  type useGetDiffEntryDataProps,
} from '../shared/use-get-diff-entry-data'
import {DiffHeaderAskCopilotButton} from './DiffHeaderAskCopilotButton'
import {InjectedDiffEntries} from './InjectedDiffEntries'
import {useMemo} from 'react'

const CopilotDiffChatHeaderMenuWrapper: React.FC<useGetDiffEntryDataProps> = props => {
  const {entriesData, loading, error} = useGetDiffEntryData(props)

  if (loading) return <LoadingAskCopilotButton />
  if (error instanceof GetDiffEntryDataForbiddenError) return null
  if (error) return <ErrorAskCopilotButton />

  return (
    <>
      <DiffHeaderAskCopilotButton entriesData={entriesData} />
      <InjectedDiffEntries entriesData={entriesData} />
    </>
  )
}

interface CopilotDiffChatHeaderMenuProps {
  baseOid: string
  headOid: string
  prPathName: string
}

// wrapper/loader
export const CopilotDiffChatHeaderMenu: React.FC<CopilotDiffChatHeaderMenuProps> = props => {
  // expecting a format of "/github/github/pull/1", and breaking that into constituent parts
  const wrapperProps = useMemo(() => {
    const pathParts = props.prPathName.split('/')
    if (pathParts.length < 4) return null

    const prNumber = parseInt(pathParts[4] as string, 10)
    if (isNaN(prNumber)) return null

    return {
      baseOid: props.baseOid,
      headOid: props.headOid,
      owner: pathParts[1] as string,
      repo: pathParts[2] as string,
      number: prNumber,
    }
  }, [props])

  if (!wrapperProps) return null

  return (
    <ErrorBoundary fallback={<ErrorAskCopilotButton />}>
      <CopilotDiffChatHeaderMenuWrapper {...wrapperProps} />
    </ErrorBoundary>
  )
}

import {Banner} from '@primer/react/experimental'
import {useState} from 'react'

import ExampleHeader from '../components/ExampleHeader'
import {PullTable} from '../components/PullTable'
import {useEnrichedPulls} from '../hooks/use-enriched-pulls'

export function ReactCoreExamplesEnrichedData() {
  const [showErrorState, setShowErrorState] = useState(false)
  const {
    pulls,
    isPending: isDeferredPending,
    isError: isDeferredError,
    refetch: refetchDeferred,
  } = useEnrichedPulls(showErrorState)

  return (
    <>
      <ExampleHeader
        pageTitle="Enriched Data"
        docsUrl="https://github.com/github/github/blob/master/ui/packages/react-core/future/docs/data-router/recipes/enriched-data.md"
        toggleErrorState={setShowErrorState}
      />
      {isDeferredError && (
        <Banner
          variant="warning"
          primaryAction={<Banner.PrimaryAction onClick={() => refetchDeferred()}>Retry</Banner.PrimaryAction>}
        >
          <Banner.Title>Failed to load labels. Please try again.</Banner.Title>
        </Banner>
      )}

      <PullTable pulls={pulls} isDeferredPending={isDeferredPending} isDeferredError={isDeferredError} />
    </>
  )
}

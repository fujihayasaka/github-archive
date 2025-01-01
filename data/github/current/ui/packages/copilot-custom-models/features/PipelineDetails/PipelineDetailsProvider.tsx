import {createContext, useContext, useMemo, type PropsWithChildren} from 'react'
import type {PipelineDetails} from '../../types'
import {CancelDialogProvider} from '../../components/CancelDialogProvider'
import {DeleteDialogProvider} from '../../components/DeleteDialogProvider'
import {usePipelinePolling} from '../../hooks/use-pipeline-polling'
import {isPipelineCancelable, isPipelineDeletable, isPipelinePollable} from '../../utils'

interface PipelineWithLogic extends PipelineDetails {
  canCancel: boolean
  canDelete: boolean
  canRetrain: boolean
  showRetrain: boolean
}

interface IContext {
  adminEmail: string
  bannerPipeline: PipelineWithLogic
  canViewDetails: boolean
  cardPipeline: PipelineWithLogic
  hasAnyDeployed: boolean
  isStale: boolean
  isViewingDetails: boolean
  org: string
  rateLimitResetAt: string | null
}

interface Props extends PropsWithChildren {
  adminEmail: string
  hasAnyDeployed: boolean
  isStale?: boolean
  isViewingDetails?: boolean
  org: string
  pipelineForBanner: PipelineDetails
  pipelineForCard: PipelineDetails
  rateLimitResetAt: string | null
  withinRateLimit: boolean
}

const Context = createContext<IContext | null>(null)

export function PipelineDetailsProvider({
  adminEmail,
  children,
  hasAnyDeployed,
  isStale = false,
  isViewingDetails = false,
  org,
  pipelineForBanner: initialPipelineForBanner,
  pipelineForCard: initialPipelineDetails,
  rateLimitResetAt,
  withinRateLimit,
}: Props) {
  const pipelineForBanner = usePipelinePolling({pipeline: initialPipelineForBanner})
  const pipelineForCard = usePipelinePolling({pipeline: initialPipelineDetails})

  const bannerPipeline = useMemo(() => {
    const canCancel = isPipelineCancelable(pipelineForBanner)
    const canDelete = isPipelineDeletable(pipelineForBanner)

    const isProcessing = isPipelinePollable(pipelineForBanner)
    const canRetrain = withinRateLimit && !isProcessing
    const showRetrain = !isProcessing

    return {...pipelineForBanner, canCancel, canDelete, canRetrain, showRetrain}
  }, [pipelineForBanner, withinRateLimit])

  const cardPipeline = useMemo(() => {
    const canCancel = isPipelineCancelable(pipelineForCard)
    const canDelete = isPipelineDeletable(pipelineForCard)

    const isProcessing = isPipelinePollable(pipelineForCard)
    const canRetrain = withinRateLimit && !isProcessing
    const showRetrain = !isProcessing

    return {...pipelineForCard, canCancel, canDelete, canRetrain, showRetrain}
  }, [pipelineForCard, withinRateLimit])

  const canViewDetails = !isViewingDetails

  const value = useMemo(
    () => ({
      adminEmail,
      bannerPipeline,
      canViewDetails,
      cardPipeline,
      children,
      hasAnyDeployed,
      isStale,
      isViewingDetails,
      org,
      pipelineForBanner,
      pipelineForCard,
      rateLimitResetAt,
    }),
    [
      adminEmail,
      bannerPipeline,
      canViewDetails,
      cardPipeline,
      children,
      hasAnyDeployed,
      isStale,
      isViewingDetails,
      org,
      pipelineForBanner,
      pipelineForCard,
      rateLimitResetAt,
    ],
  )

  return (
    <CancelDialogProvider>
      <DeleteDialogProvider pipelineDetails={pipelineForCard}>
        <Context.Provider value={value}>{children}</Context.Provider>
      </DeleteDialogProvider>
    </CancelDialogProvider>
  )
}

export function usePipelineDetails() {
  const context = useContext(Context)

  if (!context) {
    throw new Error('usePipelineDetails must be used within <PipelineDetailsProvider />')
  }

  return context
}

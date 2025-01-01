import {VALUES} from '@github-ui/timeline-items/Values'
import {useLocalStorage} from '@github-ui/use-safe-storage/local-storage'
import {useCallback, useId, useState} from 'react'
import {Box, Button, Text} from '@primer/react'
import {TimelineDivider} from '@github-ui/timeline-items/TimelineDivider'
import {LoadDirectionPicker} from './LoadDirectionPicker'

export type LoadMoreCallbackFn = (
  count: number,
  options?: {
    onComplete?: () => void
  },
) => void

export type LoadMoreProps = {
  numberOfRemainingItems: number
  loadFromTopFn: LoadMoreCallbackFn
  loadFromBottomFn: LoadMoreCallbackFn
  onLoadAllComplete?: () => void
  children: React.ReactNode
  type: 'load-top' | 'load-bottom'
  lastItemInTopTimelineIsComment: boolean
  firstItemInBottomTimelineIsComment: boolean
  isCurrentlyLoadingBackItems?: boolean
}

export const LoadMore = ({
  numberOfRemainingItems,
  loadFromTopFn,
  loadFromBottomFn,
  onLoadAllComplete,
  children,
  type,
  lastItemInTopTimelineIsComment,
  firstItemInBottomTimelineIsComment,
  isCurrentlyLoadingBackItems,
}: LoadMoreProps) => {
  const [isLoading, setIsLoading] = useState(false)
  const loadAllMode = numberOfRemainingItems < VALUES.timeline.maxPreloadCount
  const [isHovering, setIsHovering] = useState<'top' | 'bottom' | undefined>(undefined)
  const [loadMoreFromTopPreference, setLoadMoreFromTopPreference] = useLocalStorage(
    'loadMoreFromTopPreference',
    loadFromTopFn !== undefined,
  )
  const showBottomDivider = numberOfRemainingItems === 0 || firstItemInBottomTimelineIsComment
  const showTopDivider = lastItemInTopTimelineIsComment
  const descriptionId = useId()

  const loadMore = useCallback(
    (loadAll = false, shouldLoadFromTop = true) => {
      if (isLoading) return

      const loadCount = loadAll ? numberOfRemainingItems : VALUES.timeline.pageSize
      setIsLoading(true)
      setIsHovering(undefined)
      setLoadMoreFromTopPreference(shouldLoadFromTop)

      const onComplete = () => {
        setIsLoading(false)

        if (loadAll) onLoadAllComplete?.()
      }

      if (shouldLoadFromTop) {
        if (loadFromTopFn) {
          loadFromTopFn(loadCount, {
            onComplete,
          })
        }
      } else {
        if (loadFromBottomFn) {
          loadFromBottomFn(loadCount, {
            onComplete,
          })
        }
      }
    },
    [
      isLoading,
      loadFromBottomFn,
      loadFromTopFn,
      numberOfRemainingItems,
      onLoadAllComplete,
      setLoadMoreFromTopPreference,
    ],
  )

  const renderButton = useCallback(() => {
    return (
      <Button
        onClick={() => {
          loadMore(loadAllMode, loadAllMode || loadMoreFromTopPreference)
        }}
        inactive={isLoading}
        aria-disabled={isLoading}
        data-testid={`issue-timeline-load-more-${type}`}
        aria-describedby={descriptionId}
      >
        <Box
          sx={{
            display: 'flex',
            alignItems: 'center',
          }}
        >
          {children}
        </Box>
      </Button>
    )
  }, [children, descriptionId, isLoading, loadAllMode, loadMore, loadMoreFromTopPreference, type])

  return (
    <Box sx={{py: 2, gap: 2, display: 'flex', flexDirection: 'column'}}>
      {showTopDivider && (
        <TimelineDivider isLoading={isLoading && loadMoreFromTopPreference} isHovered={isHovering === 'top'} />
      )}
      <Box
        sx={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          flexDirection: 'row',
          borderTop: '2px solid',
          borderBottom: '2px solid',
          borderColor: 'border.muted',
          backgroundColor: 'canvas.default',
          boxShadow: 'shadow.small',
          overflowX: 'auto',
          scrollMarginTop: '100px',
          flexGrow: 1,
          py: 4,
          px: 2,
        }}
        data-testid={`issue-timeline-load-more-container-${type}`}
      >
        <Box
          sx={{
            display: 'flex',
            flexDirection: 'column',
            flexGrow: 1,
          }}
        >
          <Box sx={{display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2}}>
            <Box
              sx={{
                display: 'flex',
                alignSelf: 'center',
              }}
            >
              <Text as="h3" sx={{fontSize: 'unset', fontWeight: 'bold'}} id={descriptionId}>
                <span data-testid={`issue-timeline-load-more-count-${type}`}>{numberOfRemainingItems}</span>
                <span> remaining {numberOfRemainingItems === 1 ? <span>item</span> : <span>items</span>}</span>
              </Text>
            </Box>
            <Box sx={{display: 'flex', alignItems: 'center', gap: 2, cursor: 'pointer'}}>{renderButton()}</Box>
          </Box>
          {!loadAllMode && (
            <LoadDirectionPicker
              loadFromTopFn={() => {
                loadMore(false, true)
              }}
              loadFromBottomFn={() => {
                loadMore(false, false)
              }}
              isLoading={isLoading}
              setIsHovering={setIsHovering}
              type={type}
            />
          )}
        </Box>
      </Box>
      {showBottomDivider && (
        <TimelineDivider
          isLoading={(isLoading && !loadMoreFromTopPreference) || isCurrentlyLoadingBackItems}
          isHovered={isHovering === 'bottom'}
        />
      )}
    </Box>
  )
}

import type {SxProp} from '@primer/react'
import {Box, useTheme, Stack, Heading} from '@primer/react'
import Counter from './Counter'
import {Description} from './Description'
import List from './List'
import ProgressBar from './ProgressBar'
import {NoData} from './NoData'
import type {PropsWithChildren, ReactElement, ReactNode} from 'react'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'

import styles from './DataCard.module.css'
import {clsx} from 'clsx'

export type DataCardProps = PropsWithChildren<
  SxProp & {
    className?: string
    cardTitle?: string | ReactElement
    action?: ReactNode
    loading?: boolean
    error?: boolean
    noData?: boolean
    as?: 'h1' | 'h2' | 'h3' | 'h4' | 'h5' | 'h6'
  }
>

function DataCardBody({
  loading,
  error,
  noData,
  children,
}: Pick<DataCardProps, 'loading' | 'error' | 'noData' | 'children'>) {
  const {theme} = useTheme()
  const textDescriptionHeight = parseInt(theme?.fontSizes[0]) * theme?.lineHeights.default
  if (loading) {
    return (
      <>
        <LoadingSkeleton
          data-testid="data-card-loading-skeleton"
          sx={{
            height: theme?.fontSizes[4],
          }}
          variant="rounded"
          className={styles.LoadingSkeleton}
        />
        <LoadingSkeleton
          sx={{
            height: textDescriptionHeight,
          }}
          variant="rounded"
          className={styles.LoadingSkeleton_1}
        />
      </>
    )
  }

  if (error) {
    return <Description className={styles.Description}>Data could not be loaded right now</Description>
  }

  if (noData) {
    return (
      <>
        <NoData />
        <Description>No data exists for this metric with the given filters.</Description>
      </>
    )
  }

  if (children) {
    return <>{children}</>
  }

  return (
    <>
      <NoData />
      <Description>No data exists for this metric.</Description>
    </>
  )
}

function DataCard({loading, error, noData, children, cardTitle, action, sx, as = 'h3', ...otherProps}: DataCardProps) {
  const cardStyle = {
    borderWidth: 1,
    borderStyle: 'solid',
    borderColor: 'border.default',
    borderRadius: 6,
    width: '270px',
    paddingTop: '12px',
    paddingBottom: '6px',
    paddingX: '16px',
    flexGrow: 1,
    ...sx,
  }

  return (
    <Box sx={cardStyle} {...otherProps}>
      <Stack direction="horizontal" justify="space-between">
        {cardTitle && (
          <Heading className={clsx('mb-2', styles.Heading)} as={as}>
            {cardTitle}
          </Heading>
        )}
        {action}
      </Stack>
      <DataCardBody loading={loading} error={error} noData={noData}>
        {children}
      </DataCardBody>
    </Box>
  )
}

//Child Components
// Path: ui/packages/data-card/Description.tsx
DataCard.Description = Description
// Path: ui/packages/data-card/Counter.tsx
DataCard.Counter = Counter
// Path: ui/packages/data-card/ProgressBar.tsx
DataCard.ProgressBar = ProgressBar
// Path: ui/packages/data-card/List.tsx
DataCard.List = List

export default DataCard

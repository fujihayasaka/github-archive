// All styles taken from the previously used Skeleton in ui/packages/skeleton/LoadingSkeleton.tsx
import {SkeletonBox} from '@primer/react/experimental'
import type {FC} from 'react'
import {useEffect, useState} from 'react'
import styles from './IssuesLoadingSkeleton.module.css'

type SizeOption = 'sm' | 'md' | 'lg' | 'xl' | 'random'
type BorderRadiusOption = 'rounded' | 'pill' | 'elliptical'

const sizeMap: Record<Exclude<SizeOption, 'random'>, number> = {
  sm: 16,
  md: 20,
  lg: 24,
  xl: 32,
}

const borderRadiusMap: Record<BorderRadiusOption, number | string> = {
  rounded: '3px',
  pill: '100px',
  elliptical: '50%',
}

interface IssuesLoadingSkeletonProps {
  height: SizeOption | string | number
  width: SizeOption | string | number
  borderRadius?: BorderRadiusOption | string | number
}

// always returns a width between `40%` and `79%` because it generates a random integer between 0 and 39, adds 40 to it
// and then converts it to a percentage string
// taken from the previously used Skeleton in ui/packages/skeleton/LoadingSkeleton.tsx
const getRandomWidth = (): string => {
  return `${Math.floor(Math.random() * 40 + 40)}%`
}

export const IssuesLoadingSkeleton: FC<IssuesLoadingSkeletonProps> = ({height, width, borderRadius = 'rounded'}) => {
  const [randomWidth, setRandomWidth] = useState<string>('100%')

  useEffect(() => {
    if (width === 'random') {
      setRandomWidth(getRandomWidth())
    }
  }, [width])

  const calculatedHeight =
    typeof height === 'string' && height in sizeMap ? `${sizeMap[height as Exclude<SizeOption, 'random'>]}px` : height

  const calculatedWidth =
    width === 'random'
      ? randomWidth
      : typeof width === 'string' && width in sizeMap
        ? `${sizeMap[width as Exclude<SizeOption, 'random'>]}px`
        : width
  const calculatedBorderRadius =
    typeof borderRadius === 'string' && borderRadius in borderRadiusMap
      ? borderRadiusMap[borderRadius as BorderRadiusOption]
      : borderRadius

  return (
    <SkeletonBox
      data-testid="issues-loading-skeleton"
      className={styles.container}
      style={{
        width: calculatedWidth,
        height: calculatedHeight,
        borderRadius: calculatedBorderRadius,
      }}
    />
  )
}

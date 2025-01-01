import {useCallback, useEffect, useId, useRef, useState, type RefObject} from 'react'
// import {motion} from 'framer-motion'
import styles from './NodeConnection.module.css'
import {useResizeObserver} from '@primer/react'
import {usePipesStateLens} from '../../contexts/PipesStateProvider'
import {useCurrentLoop} from '../../hooks/use-current-loop'

interface NodeConnectionProps {
  containerRef: RefObject<HTMLDivElement>
  from: string
  to: string
  isSplit?: boolean
}

type LineProps = {x1: number; y1: number; x2: number; y2: number; hingePointY: number; isHorizontal: boolean}

export function NodeConnection({containerRef, from, to, isSplit = false}: NodeConnectionProps) {
  const pipeline = useCurrentLoop()
  const iteration = usePipesStateLens(s => s.executionState.iteration)
  const wrapperElement = useRef<SVGSVGElement>(null)
  const id = useId()
  const [lineProps, setLineProps] = useState<LineProps>({
    x1: 0,
    y1: 0,
    x2: 0,
    y2: 0,
    hingePointY: 0,
    isHorizontal: false,
  })

  const gradientId = `gradient-${id}`
  const maskId = `mask-${id}`
  const pathId = `path-${id}`

  const updateLine = useCallback(() => {
    const wrapperRect = wrapperElement.current?.getBoundingClientRect()
    if (!wrapperRect) return

    const fromElement = document.querySelector(`.${from}`) as HTMLElement
    const toElement = document.querySelector(`.${to}`) as HTMLElement

    if (!fromElement || !toElement) return

    const fromRect = fromElement.getBoundingClientRect()
    const toRect = toElement.getBoundingClientRect()

    const fromRectCenter = {
      x: fromRect.left + fromRect.width / 2 - wrapperRect.left,
      y: fromRect.top + fromRect.height / 2 - wrapperRect.top,
    }
    const toRectCenter = {
      x: toRect.left + toRect.width / 2 - wrapperRect.left,
      y: toRect.top + toRect.height / 2 - wrapperRect.top,
    }

    const isHorizontal = Math.abs(fromRectCenter.y - toRectCenter.y) < isHorizontalMaxDiff

    const hingePointY = isHorizontal ? fromRectCenter.y : Math.max(fromRect.top, toRect.top) - wrapperRect.top - 15

    setLineProps({
      x1: fromRectCenter.x,
      y1: fromRectCenter.y,
      x2: toRectCenter.x,
      y2: toRectCenter.y,
      isHorizontal,
      hingePointY,
    })
  }, [from, to])

  useResizeObserver(() => updateLine(), containerRef)

  useEffect(() => {
    updateLine()
  }, [from, to, pipeline, iteration, updateLine])

  const pulseLength = 30
  const rotation = Math.atan2(lineProps.y2 - lineProps.y1, lineProps.x2 - lineProps.x1) * (180 / Math.PI)

  return (
    <svg aria-hidden ref={wrapperElement} className={styles.svg}>
      {/* this is the mask and gradient that will be applied on the pulse (beam light) */}
      <defs>
        <linearGradient id={gradientId} x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="30%" stopColor="var(--borderColor-emphasis)" stopOpacity={0} />
          <stop offset="100%" stopColor="currentColor" stopOpacity={1} />
        </linearGradient>
        <mask id={maskId}>
          <path d={getLinePath(lineProps)} stroke="white" strokeWidth={2} fill="none" />
        </mask>
      </defs>
      <path
        d={getLinePath(lineProps)}
        id={pathId}
        className="stroke-borderColor-default"
        stroke="currentColor"
        strokeWidth={1}
        fill="none"
        // initial={{pathLength: 0, opacity: 0}}
        // animate={{pathLength: 1, opacity: 1}}
        // transition={{duration: 0.5, ease: 'easeInOut'}}
      />
      {/* animate a pulse (beam light) along the path to indicate the direction of the flow */}
      <g mask={`url(#${maskId})`}>
        <circle r={pulseLength} fill={`url(#${gradientId})`} transform={`rotate(${rotation})`}>
          <animateMotion dur="5000ms" repeatCount="indefinite">
            <mpath href={`#${pathId}`} />
          </animateMotion>
        </circle>
      </g>
      {isSplit &&
        getSplitLinePaths(lineProps).map(path => (
          <path
            key={path}
            d={path}
            // initial={{pathLength: 0, opacity: 0}}
            // animate={{pathLength: 1, opacity: 1}}
            // transition={{duration: 0.5, delay: 0.3, ease: 'easeInOut'}}
            stroke="currentColor"
            strokeWidth={1}
            fill="none"
          />
        ))}
    </svg>
  )
}

const isHorizontalMaxDiff = 10
const curveRadius = 20
const getLinePath = (props: LineProps) => {
  return [
    `M ${props.x1} ${props.y1}`,
    ...(Math.abs(props.x1 - props.x2) > curveRadius
      ? [
          `L ${props.x1} ${props.hingePointY - curveRadius}`,
          `Q ${props.x1}
            ${props.hingePointY}
            ${props.x1 + curveRadius * (props.x1 < props.x2 ? 1 : -1)}
            ${props.hingePointY}`,
          `L ${props.x2 - curveRadius * (props.x1 < props.x2 ? 1 : -1)} ${props.hingePointY}`,
          `Q ${props.x2} ${props.hingePointY} ${props.x2} ${props.hingePointY + curveRadius}`,
          `L ${props.x2} ${props.y2}`,
        ]
      : [`L ${props.x2} ${props.hingePointY},`, `L ${props.x2} ${props.y2}`]),
  ].join(' ')
}

const getSplitLinePaths = (props: LineProps) => {
  const shift = 3
  // draw a line shifted left and a line shifted right
  return [
    getLinePath({
      x1: props.x1 - shift,
      y1: props.y1 + shift,
      x2: props.x2 - shift,
      y2: props.y2 + shift,
      hingePointY: props.hingePointY - shift,
      isHorizontal: props.isHorizontal,
    }),
    getLinePath({
      x1: props.x1 + shift,
      y1: props.y1 - shift,
      x2: props.x2 + shift,
      y2: props.y2 - shift,
      hingePointY: props.hingePointY + shift,
      isHorizontal: props.isHorizontal,
    }),
  ]
}

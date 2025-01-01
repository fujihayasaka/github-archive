import {useId, useMemo} from 'react'
import styles from './CompactStyleEdge.module.css'
import {useEdgeStatus, type Status} from '../../../state/lenses'
import {clsx} from 'clsx'
import {useTheme} from '@primer/react'

interface PipelineEdgeProps {
  path: string
  source: string
  target: string
  isProcessing?: boolean
}

export const CompactStyleEdge: React.FC<PipelineEdgeProps> = ({path, source, target}) => {
  const id = useId()
  const theme = useTheme()
  const status: Status = useEdgeStatus(source, target)

  const maskId = `mask-${id}`
  const pathId = `path-${id}`
  const gradIdle = `idle-grad-${id}`
  const gradProc = `proc-grad-${id}`
  const idleFillColor = theme.colorScheme?.includes('dark') || theme.colorScheme?.includes('night') ? '#CCC' : '#333'

  // random delay only for IDLE
  const delay = useMemo(() => `${1 + Math.random() * 2}s`, [])

  const renderEdgeAddOn = () => {
    if (status === 'IDLE' || status === 'PROCESSING') {
      return (
        <g
          mask={`url(#${maskId})`}
          className={clsx(
            styles.edgeAddon,
            status === 'IDLE' && styles.edgeIdleAddon,
            status === 'PROCESSING' && styles.edgeProcAddon,
          )}
        >
          <circle r={status === 'IDLE' ? 25 : 30} fill={`url(#${status === 'IDLE' ? gradIdle : gradProc})`}>
            <animateMotion
              rotate="auto"
              dur={status === 'IDLE' ? '6s' : '2s'}
              begin={status === 'IDLE' ? delay : '0s'}
              repeatCount="indefinite"
            >
              <mpath href={`#${pathId}`} />
            </animateMotion>
          </circle>
        </g>
      )
    }

    if (status === 'COMPLETED')
      return (
        <path
          d={path}
          strokeWidth={2}
          fill="none"
          strokeLinecap="round"
          strokeLinejoin="round"
          className={styles.edgeCompletedAddOn}
        />
      )
  }

  return (
    <g>
      <defs>
        {/* For Idle */}
        <linearGradient id={gradIdle} x1="0%" x2="100%" y1="0%" y2="0%">
          <stop stopColor={idleFillColor} stopOpacity="0" offset="0%" />
          <stop stopColor={idleFillColor} stopOpacity="0.6" offset="100%" />
        </linearGradient>

        {/* For Processing */}
        <linearGradient id={gradProc} x1="0%" x2="100%" y1="0%" y2="0%">
          <stop stopColor="#007bff" stopOpacity="0" offset="0%" />
          <stop stopColor="#007bff" stopOpacity="1" offset="100%" />
        </linearGradient>

        <mask id={maskId}>
          <path
            d={path}
            stroke="white"
            strokeWidth={status === 'PROCESSING' ? 2.5 : 1.5}
            fill="none"
            strokeLinecap="round"
          />
        </mask>
      </defs>

      <path
        d={path}
        id={pathId}
        className={clsx(
          styles.edge,
          (status === 'IDLE' || status === 'PROCESSING') && styles.edgeDefault,
          status === 'ERROR' && styles.edgeError,
          status === 'COMPLETED' && styles.edgeCompleted,
        )}
        strokeWidth={2}
        fill="none"
      />
      {renderEdgeAddOn()}
    </g>
  )
}

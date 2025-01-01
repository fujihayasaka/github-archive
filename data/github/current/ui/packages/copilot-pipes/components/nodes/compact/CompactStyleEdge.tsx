import {useId} from 'react'

interface PipelineEdgeProps {
  path: string
  isProcessing?: boolean
}

export const CompactStyleEdge: React.FC<PipelineEdgeProps> = ({path, isProcessing = false}) => {
  const id = useId()

  const maskId = `mask-${id}`
  const pathId = `path-${id}`

  return (
    <g>
      <defs>
        <mask id={maskId}>
          <path d={path} stroke="white" strokeWidth={1} fill="none" />
        </mask>
      </defs>

      {/* Base path */}
      <path
        d={path}
        id={pathId}
        className="stroke-borderColor-default"
        stroke={`url(#lineGradient)`}
        strokeWidth={1.6}
        opacity={0.6}
        fill="none"
      />

      {isProcessing ? (
        <path
          d={path}
          stroke={`url(#activeEdgeGradient)`}
          strokeWidth={2}
          fill="none"
          strokeLinecap="round"
          strokeLinejoin="round"
          style={{
            strokeDasharray: '5% 100%',
            animation: 'activeFlowAnimation 3.5s ease-out infinite',
          }}
        />
      ) : (
        <path
          id={pathId}
          d={path}
          className="stroke-borderColor-muted"
          stroke={`url(#dotGradient)`}
          strokeWidth={3}
          fill="none"
          strokeLinecap="round"
          strokeLinejoin="round"
          style={{
            strokeDasharray: '0.5 100',
            animation: 'flowAnimation 10s ease-in-out infinite',
          }}
        />
      )}
    </g>
  )
}

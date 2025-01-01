import {forwardRef, useMemo} from 'react'

interface SvgBorderProps {
  gradient: Gradient[]
  gradientType?: 'linear' | 'radial'
  shape?: 'rect' | 'circle'
  borderRadius?: number | string
  thickness?: number
  className?: string
  // Linear gradient
  x1?: number
  y1?: number
  x2?: number
  y2?: number
  // Radial gradient
  r?: number
  cx?: number
  cy?: number
  fx?: number
  fy?: number
}

const defaultProps: Partial<SvgBorderProps> = {
  gradientType: 'linear',
  shape: 'rect',
  borderRadius: 0,
  x1: 0,
  y1: 0,
  x2: 100,
  y2: 100,
  r: 50,
  cx: 50,
  cy: 50,
  fx: 50,
  fy: 50,
  thickness: 1,
}

export interface Gradient {
  color: string
  offset: number
  opacity?: number
}

const SvgBorder = forwardRef<SVGSVGElement, SvgBorderProps>((props, ref) => {
  const initializedProps = {...defaultProps, ...props} as Required<SvgBorderProps>
  const {gradient, gradientType, shape, borderRadius, thickness, className, r, cx, cy, fx, fy, x1, y1, x2, y2} =
    initializedProps

  const gradientStops = useMemo(
    () =>
      gradient.map(({color, offset, opacity = 1}, index) => (
        // eslint-disable-next-line @eslint-react/no-array-index-key
        <stop key={`stop_${index}`} offset={`${offset}%`} style={{stopColor: color, stopOpacity: opacity}} />
      )),
    [gradient],
  )

  return (
    <svg width="100%" height="100%" role="presentation" ref={ref} className={className}>
      <defs>
        {gradientType === 'linear' && (
          <linearGradient id="gradient" x1={`${x1}%`} y1={`${y1}%`} x2={`${x2}%`} y2={`${y2}%`}>
            {gradientStops}
          </linearGradient>
        )}
        {gradientType === 'radial' && (
          <radialGradient id="gradient" cx={`${cx}%`} cy={`${cy}%`} r={`${r}%`} fx={`${fx}%`} fy={`${fy}%`}>
            {gradientStops}
          </radialGradient>
        )}
      </defs>

      {shape === 'rect' && (
        <rect
          x={thickness}
          y={thickness}
          width={`calc(100% - ${2 * thickness}px)`}
          height={`calc(100% - ${2 * thickness}px)`}
          rx={borderRadius}
          ry={borderRadius}
          stroke="url(#gradient)"
          strokeWidth={thickness}
          fill="transparent"
        />
      )}

      {shape === 'circle' && (
        <circle
          cx="50%"
          cy="50%"
          r={`calc(50% - ${thickness}px)`}
          stroke="url(#gradient)"
          strokeWidth={thickness}
          fill="transparent"
        />
      )}
    </svg>
  )
})

SvgBorder.displayName = 'SvgBorder'

export default SvgBorder

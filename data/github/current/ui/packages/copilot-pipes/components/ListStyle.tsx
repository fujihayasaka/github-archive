import {useNodeError, useNode} from '../state/lenses'
import type React from 'react'

interface ListStyleProps {
  nodeId: string
  depth: number
  isLoading: boolean
  isSelected: boolean
  isHighlighted: boolean
  onClick: () => void
}

export const ListStyle: React.FC<ListStyleProps> = ({nodeId, depth, isLoading, isSelected, isHighlighted, onClick}) => {
  const node = useNode(nodeId)
  const error = useNodeError(nodeId)

  if (!node) return null
  return (
    <button
      onClick={onClick}
      className={`
        w-full text-left px-3 py-2 rounded-xl border
        transition-colors duration-100
        ${
          isSelected
            ? 'bg-bgColor-default border-borderColor-default'
            : isHighlighted
              ? 'hover:bg-bgColor-default border-transparent'
              : 'hover:bg-bgColor-default border-transparent'
        }
      `}
      style={{paddingLeft: `${depth * 1 + 0.75}rem`}}
    >
      <div className="flex gap-2 w-full">
        <div
          className={`
          w-2 h-2 rounded-full flex-shrink-0 mt-1.5
          ${isLoading ? 'bg-blue-500 animate-ping' : error ? 'bg-red-500' : 'bg-neutral-200'}
        `}
        />

        <div className="flex-1 min-w-0">
          <div className="text-sm font-medium truncate">
            <span className="inline-block mr-1 py-[0.5em] px-[0.8em] bg-bgColor-muted rounded-md text-[10px] leading-none font-semibold text-fgColor-muted font-mono border border-borderColor-muted align-[10%]">
              {node.id}
            </span>
            {node.title}
          </div>
          {node.description && <div className="text-xs text-neutral-500 line-clamp-3">{node.description}</div>}
        </div>
      </div>
    </button>
  )
}

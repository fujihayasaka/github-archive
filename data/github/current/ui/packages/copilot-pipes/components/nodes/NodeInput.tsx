import type React from 'react'
import {clsx} from 'clsx'
import {TextInput, Checkbox, Select} from '@primer/react'
import styles from './NodeInput.module.css'
import {ContentEditor} from '../controls/ContentEditor'
import {useNode} from '../../state/lenses'

interface NodeInputProps {
  nodeId: string
  onChange: (value: string) => void
  className?: string
}

export const NodeInput: React.FC<NodeInputProps> = ({nodeId, onChange, className}) => {
  const node = useNode(nodeId)

  if (!node || node.type !== 'text') return null

  switch (node.inputType.type) {
    case 'range':
      return (
        <div>
          <div className={styles.rangeValue}>{node.content}</div>
          <div className={styles.rangeContainer}>
            <input
              type="range"
              value={node.content || '0'}
              min={node.inputType.min}
              max={node.inputType.max}
              onChange={e => onChange(e.target.value)}
              className={className}
            />
          </div>
          <div className={styles.rangeLabels}>
            <div className={styles.rangeLabel}>{node.inputType.min}</div>
            <div className={styles.rangeLabel}>{node.inputType.max}</div>
          </div>
        </div>
      )

    case 'boolean':
      return (
        <div className={styles.booleanContainer}>
          <Checkbox
            checked={node.content === 'true'}
            onChange={e => onChange(e.target.checked.toString())}
            className={className}
          />
        </div>
      )

    case 'select':
      return (
        <div>
          <Select value={node.content} onChange={e => onChange(e.target.value)} className={className}>
            {node.inputType.options?.map((option: string) => (
              <Select.Option key={option} value={option}>
                {option}
              </Select.Option>
            ))}
          </Select>
        </div>
      )

    case 'file':
      return (
        <div>
          <TextInput
            type="file"
            value={node.content}
            accept={getFileTypeAccept(node.inputType.fileType)}
            onChange={e => {
              const file = e.target.files?.[0]
              if (file) {
                onChange(file.name)
              }
            }}
            className={clsx(className, styles.fileContainer)}
          />
        </div>
      )

    case 'text':
    default:
      return <ContentEditor content={node.content} onUpdate={onChange} placeholder="Enter value" />
  }
}

function getFileTypeAccept(fileType: string): string {
  switch (fileType) {
    case 'pdf':
      return '.pdf'
    case 'image':
      return 'image/*'
    case 'video':
      return 'video/*'
    case 'audio':
      return 'audio/*'
    case 'document':
      return '.doc,.docx,.txt,.rtf'
    case 'code':
      return '.js,.jsx,.ts,.tsx,.py,.java,.cpp,.c,.h,.cs'
    default:
      return '*/*'
  }
}

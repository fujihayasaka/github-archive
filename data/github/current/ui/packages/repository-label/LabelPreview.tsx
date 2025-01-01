import {LabelToken} from '@github-ui/label-token'
import styles from './LabelPreview.module.css'
import {SafeHTMLText, type SafeHTMLString} from '@github-ui/safe-html'

type LabelPreviewProps = {
  /**
   * The HTML string of the label name
   */
  nameHTML?: SafeHTMLString
  /**
   * The label name
   */
  name: string
  /**
   * The color of the label
   */
  color: string
}

export function LabelPreview({nameHTML, name, color}: LabelPreviewProps) {
  const labelText = nameHTML ? <SafeHTMLText html={nameHTML} /> : name || ''

  return (
    <div className={styles.container}>
      <LabelToken
        text={labelText}
        fillColor={`#${color}`}
        aria-label={name}
        // LabelToken does not support className yet.
        style={{
          overflow: 'hidden',
          textOverflow: 'ellipsis',
          cursor: 'pointer',
          maxWidth: '100%',
        }}
      />
    </div>
  )
}

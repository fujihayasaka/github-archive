import type {Image} from './content-preview-types'
import styles from './ImagePreview.module.css'

export function ImagePreview({image}: {image: Image}) {
  return (
    <div className={styles.container}>
      <img className={styles.imageElement} src={image.url} alt={image.altText} />
    </div>
  )
}

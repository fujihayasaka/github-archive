import styles from './Description.module.css'

type DescriptionProps = {
  children: React.ReactNode | string
}

const Description = ({children}: DescriptionProps) => {
  if (typeof children === 'string') {
    return (
      <div className={styles.container}>
        <p className={styles.text}>{children}</p>
      </div>
    )
  }

  return <span className={styles.container}>{children}</span>
}
Description.displayName = 'Description'

export default Description

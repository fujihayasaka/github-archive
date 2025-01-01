import styles from './Banners.module.css'

function Banners({children}: React.PropsWithChildren): JSX.Element {
  return <div className={styles.Box}>{children}</div>
}

Banners.displayName = 'PageLayout.Banners'

export default Banners

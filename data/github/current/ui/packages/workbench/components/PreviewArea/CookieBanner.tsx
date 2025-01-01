import styles from './CookieBanner.module.css'

export function CookieBanner({hideCookieBanner}: {hideCookieBanner: () => void}) {
  return (
    <div className={styles.container}>
      <h2 className={styles.title}>⚠️ Cookie Support Required for App Preview</h2>

      <div className={styles.content}>
        <section>
          <h3 className={styles.sectionTitle}>Recommended Action</h3>
          <p>
            Please{' '}
            <a
              href="https://gh.io/apple-support-upgrade-safari"
              className={styles.link}
              target="_blank"
              rel="noopener noreferrer"
            >
              upgrade your Safari browser
            </a>{' '}
            to version <strong>18.4 or newer</strong>. This is required because Spark preview page needs partitioned
            cookie support to function properly.
          </p>
        </section>

        <section>
          <h3 className={styles.sectionTitle}>Alternative Solution</h3>
          <p>
            If you cannot upgrade your browser, you can enable third-party cookies in your current Safari version.{' '}
            <a
              href="https://gh.io/apple-support-prevent-cross-site-tracking-safari"
              className={styles.link}
              target="_blank"
              rel="noopener noreferrer"
            >
              Learn why this option is not preferred
            </a>
          </p>
          <div className={styles.instructions}>
            <h4 className={styles.sectionTitle}>Instructions:</h4>
            <ol className={styles.orderedList}>
              <li>Open Safari {'>'} Settings...</li>
              <li>
                Turn off the following settings:
                <ul className={styles.unorderedList}>
                  <li>Advanced {'>'} Block all cookies</li>
                  <li>Privacy {'>'} Prevent cross-site tracking</li>
                </ul>
              </li>
            </ol>
          </div>
        </section>

        <div className={styles.checkboxWrapper}>
          <label className={styles.checkboxLabel}>
            <input type="checkbox" onChange={() => hideCookieBanner()} className={styles.checkbox} />
            <span>I have enabled third-party cookies</span>
          </label>
        </div>
      </div>
    </div>
  )
}

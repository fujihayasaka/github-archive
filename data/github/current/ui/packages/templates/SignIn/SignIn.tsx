import {TextInput, FormControl, Button, Link} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {MarkGithubIcon} from '@primer/octicons-react'

import Footer from './Footer'

import styles from './SignIn.module.css'

export function SignIn() {
  return (
    <div className={styles.Box}>
      <main className={styles.Box_1}>
        <div className={styles.Box_2}>
          <div className={styles.Box_3}>
            <Octicon icon={MarkGithubIcon} size={48} />
            <h1 className={styles.Text}>Sign in to GitHub</h1>
          </div>
          <div className={styles.Box_4}>
            <form className={styles.Box_5}>
              <FormControl>
                <FormControl.Label>Username or email address</FormControl.Label>
                <TextInput type="text" block autoFocus />
              </FormControl>
              <FormControl id="password">
                <div className={styles.Box_6}>
                  <label htmlFor="password" className={styles.Text_1}>
                    Password
                  </label>
                  <Link href="https://github.com/password_reset" className={styles.Link}>
                    Forgot password?
                  </Link>
                </div>
                <div className={styles.Box_7}>
                  <TextInput type="password" id="password" block />
                </div>
              </FormControl>
              <Button variant="primary">Sign in</Button>
            </form>
            <div className={styles.Box_8}>
              New to GitHub?{' '}
              <Link inline href="https://github.com/signup">
                Create an account
              </Link>
            </div>
          </div>
        </div>
      </main>
      <Footer />
    </div>
  )
}

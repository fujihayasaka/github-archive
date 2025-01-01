import {generateDefaultModel} from '@github-ui/copilot-chat/utils/models'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {useNavigate} from '@github-ui/use-navigate'
import {reactFetch} from '@github-ui/verified-fetch'
import {MarkGithubIcon} from '@primer/octicons-react'
import {Button, Dialog, Stack} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {useRef, useState} from 'react'

import {useCopilotContext} from '../contexts/CopilotContext'
import type {CopilotImmersiveLoggedOutPayload} from '../copilot-immersive-logged-out-types'
import styles from './SignInDialog.module.css'

interface SignInDialogProps {
  onClose: () => void
}

export const SignInDialog = ({onClose}: SignInDialogProps) => {
  const {promptPath} = useAppPayload<CopilotImmersiveLoggedOutPayload>()
  const signInButtonRef = useRef<HTMLButtonElement>(null)
  const navigate = useNavigate()
  const [error, setError] = useState('')

  const {
    prompt,
    selectedModel: {id: model},
  } = useCopilotContext()
  const modelIsSelected = model !== generateDefaultModel().id

  const handleSignIn = () => {
    void handleClick('sign_in')
  }

  const handleSignUp = () => {
    void handleClick('sign_up')
  }

  const handleClick = async (via: string) => {
    const formData = new FormData()

    formData.append('via', via)
    formData.append('prompt', prompt)

    if (modelIsSelected) {
      formData.append('model', model)
    }

    try {
      const res = await reactFetch(promptPath, {method: 'POST', body: formData})

      if (res.redirected) {
        navigate(res.url)
      } else {
        setError('Something went wrong!')
      }
    } catch {
      setError('Something went wrong!')
    }
  }

  return (
    <Dialog
      aria-label="Sign in to GitHub Copilot"
      className={styles.signInDialog}
      initialFocusRef={signInButtonRef}
      onClose={onClose}
      title=""
      width="medium"
    >
      <div className={styles.iconContainer}>
        <MarkGithubIcon className={styles.dialogLogo} />
      </div>
      <Stack>
        <span className={styles.signInTitle}>Sign in to continue</span>
        <span className={styles.signInText}>Sign in or create a GitHub account to continue using Copilot.</span>
        {error && <Banner variant="critical" description={error} aria-label="Error" title="Error" hideTitle />}
        <div className={styles.buttonContainer}>
          <Button
            onClick={handleSignIn}
            variant="default"
            size="large"
            block
            ref={signInButtonRef}
            data-testid="sign-in-button"
          >
            Sign in
          </Button>
          <Button onClick={handleSignUp} variant="primary" size="large" block data-testid="sign-up-button">
            Create a free account
          </Button>
        </div>
      </Stack>
    </Dialog>
  )
}

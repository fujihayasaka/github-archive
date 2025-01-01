import {act, render, screen} from '@testing-library/react'

import {Octocaptcha} from '../../../components'

const OCTOCAPTCHA_TEST_HOSTNAME = 'octocaptcha.localhost'
const OCTOCAPTCHA_ORIGIN = `http://${OCTOCAPTCHA_TEST_HOSTNAME}`

describe('Octocaptcha', () => {
  it('shows a loading screen while loading', async () => {
    render(<Octocaptcha hostName={OCTOCAPTCHA_TEST_HOSTNAME} />)

    await expect(screen.findByRole('img')).resolves.toHaveAttribute('alt', 'Loading CAPTCHA...')
  })

  it('shows a success screen if the captcha is supressed', async () => {
    render(<Octocaptcha hostName={OCTOCAPTCHA_TEST_HOSTNAME} />)

    act(() => {
      window.dispatchEvent(
        new MessageEvent('message', {
          source: window,
          origin: OCTOCAPTCHA_ORIGIN,
          data: {event: 'captcha-suppressed'},
        }),
      )
    })

    await expect(screen.findByLabelText('Account has been verified. Please continue.')).resolves.toBeVisible()
  })

  describe('handling success', () => {
    const message = new MessageEvent('message', {
      source: window,
      origin: OCTOCAPTCHA_ORIGIN,
      data: {event: 'captcha-complete', sessionToken: 'token'},
    })

    it('sets the captcha token', async () => {
      const {container} = render(<Octocaptcha hostName={OCTOCAPTCHA_TEST_HOSTNAME} />)

      act(() => window.dispatchEvent(message))

      /* eslint-disable-next-line testing-library/no-container, testing-library/no-node-access --
       *
       * Not a user-facing element.
       */
      expect(container.querySelector('input[name="octocaptcha-token"]')).toHaveValue('token')
    })

    it('calls the onComplete callback', async () => {
      const spy = jest.fn()

      render(<Octocaptcha onComplete={spy} hostName={OCTOCAPTCHA_TEST_HOSTNAME} />)

      act(() => window.dispatchEvent(message))

      expect(spy).toHaveBeenCalledTimes(1)
      expect(spy).toHaveBeenCalledWith({token: 'token'})
    })
  })

  describe('handling load error', () => {
    it('sets error_loading_captcha', async () => {
      const {container} = render(<Octocaptcha timeoutAfter={0} hostName={OCTOCAPTCHA_TEST_HOSTNAME} />)

      // Small hack to wait for the timeout to be reached. It clears the execution stack.
      await act(async () => sleep(0))

      /* eslint-disable-next-line testing-library/no-container, testing-library/no-node-access --
       *
       * Not a user-facing element.
       */
      expect(container.querySelector('input[name="error_loading_captcha"]')).toHaveValue('1')
    })

    it('does not set error_loading_captcha if the captcha was suppressed', async () => {
      const {container} = render(<Octocaptcha timeoutAfter={0} hostName={OCTOCAPTCHA_TEST_HOSTNAME} />)

      act(() =>
        window.dispatchEvent(
          new MessageEvent('message', {
            source: window,
            origin: OCTOCAPTCHA_ORIGIN,
            data: {event: 'captcha-suppressed'},
          }),
        ),
      )

      // Small hack to wait for the timeout to be reached. It clears the execution stack.
      await act(async () => sleep(0))

      /* eslint-disable-next-line testing-library/no-container, testing-library/no-node-access --
       *
       * Not a user-facing element.
       */
      expect(container.querySelector('input[name="error_loading_captcha"]')).toBeNull()
    })

    it('calls the onLoadError callback', async () => {
      const spy = jest.fn()

      render(<Octocaptcha onLoadError={spy} timeoutAfter={0} hostName={OCTOCAPTCHA_TEST_HOSTNAME} />)

      // Small hack to wait for the timeout to be reached. It clears the execution stack.
      await act(async () => sleep(0))

      expect(spy).toHaveBeenCalledTimes(1)
    })
  })
})

const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms))

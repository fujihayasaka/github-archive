import {render} from '@github-ui/react-core/test-utils'
import {act, screen, within} from '@testing-library/react'
import React from 'react'

import {type DialogRef, InterviewSurveyDialog} from '../InterviewSurveyDialog'

it('renders closed', () => {
  render(<InterviewSurveyDialog />)
  expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
})

describe('openDialog', () => {
  it('opens interview survey dialog', async () => {
    const dialogRef = React.createRef<DialogRef>()
    render(<InterviewSurveyDialog ref={dialogRef} />)

    act(() => dialogRef.current?.openDialog())

    const dialog = await screen.findByRole('dialog')
    expect(dialog).toBeInTheDocument()

    // Look for things identifying the feedback dialog
    expect(await within(dialog).findByRole('link', {name: /book a session/i})).toBeInTheDocument()
  })
})

describe('user closes dialog', () => {
  describe('by clicking the "Close" button', () => {
    it('calls onClose with reason "close"', async () => {
      const onClose = jest.fn()
      const dialogRef = React.createRef<DialogRef>()
      const {user} = render(<InterviewSurveyDialog ref={dialogRef} onClose={onClose} />)

      act(() => dialogRef.current?.openDialog())

      const dialog = await screen.findByRole('dialog')
      expect(dialog).toBeInTheDocument()

      await user.click(await within(dialog).findByRole('button', {name: /close/i}))

      expect(onClose).toHaveBeenCalledWith('close')
      expect(dialog).not.toBeInTheDocument()
    })
  })

  describe('by pressing ESC', () => {
    it('calls onClose with reason "close"', async () => {
      const onClose = jest.fn()
      const dialogRef = React.createRef<DialogRef>()
      const {user} = render(<InterviewSurveyDialog ref={dialogRef} onClose={onClose} />)

      act(() => dialogRef.current?.openDialog())

      const dialog = await screen.findByRole('dialog')
      expect(dialog).toBeInTheDocument()

      await user.keyboard('{Escape}')

      expect(onClose).toHaveBeenCalledWith('close')
      expect(dialog).not.toBeInTheDocument()
    })
  })

  describe('by clicking the "No thanks" button', () => {
    it('calls onClose with reason "no-thanks"', async () => {
      const onClose = jest.fn()
      const dialogRef = React.createRef<DialogRef>()
      const {user} = render(<InterviewSurveyDialog ref={dialogRef} onClose={onClose} />)

      act(() => dialogRef.current?.openDialog())

      const dialog = await screen.findByRole('dialog')
      expect(dialog).toBeInTheDocument()

      await user.click(await within(dialog).findByRole('button', {name: /no, thanks/i}))

      expect(onClose).toHaveBeenCalledWith('no-thanks')
      expect(dialog).not.toBeInTheDocument()
    })
  })
})

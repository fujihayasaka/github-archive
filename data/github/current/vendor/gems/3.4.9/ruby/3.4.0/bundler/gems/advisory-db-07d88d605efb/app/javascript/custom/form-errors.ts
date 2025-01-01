import { on } from 'delegated-events'

on('click', '.note .js-note-close', function (event) {
  const note = event.currentTarget.closest('.note')! as HTMLElement
  note.hidden = true
})

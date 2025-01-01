export const handleKeyInput = (
  event: React.FormEvent<HTMLInputElement>,
  inputRefs: React.MutableRefObject<HTMLInputElement[]>,
) => {
  const input = event.target as HTMLInputElement
  const thisInputIndex = inputRefs.current.indexOf(input)
  const nextInput = inputRefs.current[thisInputIndex + 1]

  if (input.checkValidity()) {
    if (nextInput) {
      // TODO: Submit the form when validity passes
      // Noted as a task here: https://github.com/github/new-user-experience/issues/400
      // if (form.checkValidity()) {
      //   this.form.submit()
      // } else {
      nextInput.focus()
      // }
    }
    // else {
    //   if (this.form.reportValidity()) this.form.submit()
    // }
  } else {
    input.value = ''
  }
}

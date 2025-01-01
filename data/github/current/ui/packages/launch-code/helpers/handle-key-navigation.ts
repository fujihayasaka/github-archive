export const handleKeyNavigation = (
  event: React.KeyboardEvent<HTMLInputElement>,
  inputRefs: React.MutableRefObject<HTMLInputElement[]>,
): void => {
  // TODO: Refactor to use data-hotkey (old todo from 2021, check if this is still relevant)
  /* eslint eslint-comments/no-use: off */
  /* eslint-disable @github-ui/ui-commands/no-manual-shortcut-logic */
  const navigationKeys = ['Backspace', 'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown']
  if (!navigationKeys.includes(event.key)) return

  const input = event.target as HTMLInputElement
  const thisInputIndex = inputRefs.current.indexOf(input)
  const nextInput = inputRefs.current[thisInputIndex + 1]

  switch (event.key) {
    case 'Backspace': {
      const previousInput = inputRefs.current[thisInputIndex - 1]
      if (previousInput) {
        previousInput.focus()
        previousInput.value = ''
      }
      return
    }
    case 'ArrowLeft': {
      const previousInput = inputRefs.current[thisInputIndex - 1]
      if (previousInput) previousInput.focus()
      return
    }
    case 'ArrowRight': {
      if (nextInput) nextInput.focus()
      return
    }
    case 'ArrowUp':
    case 'ArrowDown': {
      event.preventDefault()
      return
    }
  }
  /* eslint-enable @github-ui/ui-commands/no-manual-shortcut-logic */
}

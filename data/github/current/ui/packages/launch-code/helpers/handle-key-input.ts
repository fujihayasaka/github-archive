import {checkAllFilled} from './check-all-filled'
interface HandleKeyInputProps {
  event: React.FormEvent<HTMLInputElement>
  inputRefs: React.MutableRefObject<HTMLInputElement[]>
  handleFormSubmit: () => void
}

export const handleKeyInput = ({event, inputRefs, handleFormSubmit}: HandleKeyInputProps): void => {
  const input = event.target as HTMLInputElement
  const thisInputIndex = inputRefs.current.indexOf(input)
  const nextInput = inputRefs.current[thisInputIndex + 1]

  if (input.checkValidity()) {
    if (nextInput) {
      nextInput.focus()
    } else {
      if (checkAllFilled(inputRefs)) {
        handleFormSubmit()
      }
    }
  } else {
    input.value = ''
  }
}

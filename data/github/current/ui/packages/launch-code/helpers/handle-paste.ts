import {checkAllFilled} from './check-all-filled'

interface HandlePasteProps {
  event: React.ClipboardEvent<HTMLInputElement>
  inputRefs: React.MutableRefObject<HTMLInputElement[]>
  handleFormSubmit: () => void
}

export const handlePaste = ({event, inputRefs, handleFormSubmit}: HandlePasteProps): void => {
  event.preventDefault()
  const clipboardData = event.clipboardData

  if (!clipboardData) return

  const launchCode = clipboardData.getData('text')

  const launchCodeRegExp = new RegExp(`^${'[0-9]'}*$`)
  if (!launchCodeRegExp.test(launchCode)) return

  for (const inputField of inputRefs.current) {
    const thisInputIndex = inputRefs.current.indexOf(inputField)

    if (launchCode[thisInputIndex] !== undefined) {
      inputField.value = launchCode[thisInputIndex]
    }
  }
  if (checkAllFilled(inputRefs)) {
    handleFormSubmit()
  }
}

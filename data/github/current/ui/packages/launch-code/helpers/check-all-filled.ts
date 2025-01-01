// Function to check if all inputs are filled
export const checkAllFilled = (inputRefs: React.MutableRefObject<HTMLInputElement[]>): boolean => {
  return inputRefs.current.every(input => input?.value.trim() !== '')
}

export const downloadFile = (file: File) => {
  const url = URL.createObjectURL(file)
  const a = document.createElement('a')
  a.href = url
  a.download = file.name || 'file'
  a.click()
  URL.revokeObjectURL(url)
}

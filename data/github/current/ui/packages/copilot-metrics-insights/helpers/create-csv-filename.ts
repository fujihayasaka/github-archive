/*
For a given metrics page, given a csv file name append the current datetime in UTC to the end and add the csv file extension
*/
export function createCsvFilename(fileName: string): string {
  return `${fileName}_${getUTCDateTimeString()}.csv`
}

export function getUTCDateTimeString(): string {
  const now = new Date()

  const year = now.getUTCFullYear()
  const month = (now.getUTCMonth() + 1).toString().padStart(2, '0')
  const day = now.getUTCDate().toString().padStart(2, '0')
  const hours = now.getUTCHours().toString().padStart(2, '0')
  const minutes = now.getUTCMinutes().toString().padStart(2, '0')
  const seconds = now.getUTCSeconds().toString().padStart(2, '0')
  return `${year}-${month}-${day}T${hours}${minutes}${seconds}Z`
}

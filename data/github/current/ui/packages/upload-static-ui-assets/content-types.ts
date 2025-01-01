import mime from 'mime'

export function getContentType(asset: string) {
  return mime.getType(asset) ?? 'application/octet-stream'
}

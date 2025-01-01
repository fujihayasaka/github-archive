import {parseTailWindClassName} from './tailwind-utils'

export async function getAttributes(
  filePath: string,
  line: number,
  column: number,
  tunnelToken: string,
  serverUrl: string,
) {
  const response = await fetch(`${serverUrl}/readAttributes?filePath=${filePath}&line=${line}&column=${column}`, {
    headers: {
      'X-Tunnel-Authorization': `tunnel ${tunnelToken}`,
    },
  })
  const {className, ...rest} = await response.json()

  const parsedTailWindClass = parseTailWindClassName(className)

  return {
    className,
    attributes: rest,
    parsedTailWindClass,
  }
}

export async function modifyElement(
  filePath: string,
  line: number,
  column: number,
  attributeName: string,
  attributeValue: string,
  serverUrl: string,
  tunnelToken: string,
): Promise<boolean> {
  const response = await fetch(`${serverUrl}/editFile`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Tunnel-Authorization': `tunnel ${tunnelToken}`,
    },
    body: JSON.stringify({
      filePath,
      line,
      column,
      attributeName,
      attributeValue,
    }),
  })

  return response.ok
}

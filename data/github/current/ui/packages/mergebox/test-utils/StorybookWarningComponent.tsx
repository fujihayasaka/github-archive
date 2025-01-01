import {Flash} from '@primer/react'

export default function StoryBookWarning(warnings: string[]) {
  if (warnings.length > 0) {
    return (
      <Flash>
        {warnings.map((s: string, i: number) => (
          // eslint-disable-next-line @eslint-react/no-array-index-key
          <p key={i}>{s}</p>
        ))}
      </Flash>
    )
  } else {
    return null
  }
}

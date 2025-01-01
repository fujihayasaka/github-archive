import {Link} from '@primer/react'

interface Props {
  indexPath: string
  newPath: string
  assessingPath: string
  assessmentPath: string
  trainingPath: string
}

export function Links({indexPath, newPath, assessingPath, assessmentPath, trainingPath}: Props) {
  return (
    <ul>
      <li>
        <Link href={indexPath}>Index</Link>
      </li>
      <li>
        <Link href={newPath}>New</Link>
      </li>
      <li>
        <Link href={assessingPath}>Assessing</Link>
      </li>
      <li>
        <Link href={assessmentPath}>Assessment</Link>
      </li>
      <li>
        <Link href={trainingPath}>Training</Link>
      </li>
    </ul>
  )
}

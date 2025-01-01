import {DiffSquares} from './DiffSquares'

const DiffStat = {
  addition: 'addition',
  deletion: 'deletion',
  neutral: 'neutral',
} as const

function buildScreenReaderHint({linesAdded, linesDeleted}: {linesAdded: number; linesDeleted: number}): string {
  let labelText = 'Lines changed: '
  labelText += `${linesAdded} ${linesAdded === 1 ? 'addition' : 'additions'} & `
  labelText += `${linesDeleted} ${linesDeleted === 1 ? 'deletion' : 'deletions'}`
  return labelText
}

export function DiffStats({
  linesAdded = 0,
  linesDeleted = 0,
  linesChanged = 0,
}: {
  linesAdded?: number
  linesDeleted?: number
  linesChanged?: number
}) {
  if ((!linesAdded && !linesDeleted && !linesChanged) || linesChanged === 0) {
    return null
  }

  const {greenSquares, redSquares, graySquares} = calculateDiffSquareCounts(linesAdded, linesDeleted, linesChanged)

  const squares: Array<(typeof DiffStat)[keyof typeof DiffStat]> = [
    ...Array<typeof DiffStat.addition>(greenSquares).fill(DiffStat.addition),
    ...Array<typeof DiffStat.deletion>(redSquares).fill(DiffStat.deletion),
    ...Array<typeof DiffStat.neutral>(graySquares).fill(DiffStat.neutral),
  ]

  return (
    <div className="d-flex flex-items-center gap-1 pl-1">
      {linesAdded > 0 && (
        <span aria-hidden="true" className="f6 text-bold fgColor-success">
          +{linesAdded.toLocaleString()}
        </span>
      )}
      {linesDeleted > 0 && (
        <span aria-hidden="true" className="f6 text-bold fgColor-danger">
          -{linesDeleted.toLocaleString()}
        </span>
      )}
      <span className="sr-only">{buildScreenReaderHint({linesAdded, linesDeleted})}</span>
      <DiffSquares squares={squares} />
    </div>
  )
}

export function calculateDiffSquareCounts(linesAdded: number, linesDeleted: number, linesChanged: number) {
  const totalSquares = 5
  // adjustment function to give a more accurate representation of the scale of the diff
  const adjust = linesChanged > totalSquares ? totalSquares / linesChanged : 1.0

  const greenSquares = Math.floor(linesAdded * adjust)
  const redSquares = Math.floor(linesDeleted * adjust)
  const graySquares = totalSquares - greenSquares - redSquares

  return {
    greenSquares,
    redSquares,
    graySquares,
  }
}

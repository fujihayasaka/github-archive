import {RowLoading} from './RowLoading'

export function RowsLoading({rowCount}: {rowCount: number}): JSX.Element {
  return (
    <>
      {Array.from(Array(rowCount).keys()).map(index => (
        <RowLoading key={index} />
      ))}
    </>
  )
}

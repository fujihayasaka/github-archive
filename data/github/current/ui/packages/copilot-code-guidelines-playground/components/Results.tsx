export default function Results({results}: {results: Array<{lineNumber: number; details: string}>}) {
  if (results.length === 0) {
    return (
      <div className="height-full d-flex flex-column flex-justify-center flex-items-center gap-2 fgColor-muted">
        No comments for this code.
      </div>
    )
  }

  return (
    <div>
      <h4 className="sr-only">Results</h4>
      {results.map((result, index) => (
        // eslint-disable-next-line @eslint-react/no-array-index-key
        <div key={index}>
          <h5 className="text-normal fgColor-muted">
            Line <span className="text-bold fgColor-default">{result.lineNumber}</span>
          </h5>
          <p>{result.details}</p>
        </div>
      ))}
    </div>
  )
}

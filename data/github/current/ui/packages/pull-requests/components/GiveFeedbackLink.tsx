import {Label, Link} from '@primer/react'

export function GiveFeedbackLink({url}: {url: string}) {
  return (
    <div className="d-flex mt-2 flex-shrink-0 flex-justify-end">
      <Link href={url} target="_blank" className="no-wrap">
        <Label className="mr-2" variant="success">
          Beta
        </Label>
        Give feedback
      </Link>
    </div>
  )
}

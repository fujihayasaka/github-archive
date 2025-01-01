import type React from 'react'
import {Button, Link as PrimerLink} from '@primer/react'
import {Link} from '@github-ui/react-core/link'
import {testIdProps} from '@github-ui/test-id-props'

interface BlankSlate {
  header: string
  message: string
  url: string
  linkText: string
  newConfigButtonPath?: string
}

const BlankSlate: React.FC<BlankSlate> = ({header, message, url, linkText, newConfigButtonPath}) => {
  return (
    <div className="border rounded-2 p-5" {...testIdProps('blankslate')}>
      <p className="f3 text-bold text-center" data-hpc>
        {header}
      </p>
      <p className="f4 fgColor-muted text-center">
        {message}
        {/* inline Pimer prop is not working properly with as= so we will continue to use our styling here */}
        <PrimerLink as={Link} to={url} className="Link--inTextBlock">
          {linkText}
        </PrimerLink>
        .
      </p>
      {newConfigButtonPath && (
        <p className="m-0 mt-5 text-center">
          <Button data-testid="new-configuration" as={Link} to={newConfigButtonPath} variant="primary">
            New configuration
          </Button>
        </p>
      )}
    </div>
  )
}

export default BlankSlate

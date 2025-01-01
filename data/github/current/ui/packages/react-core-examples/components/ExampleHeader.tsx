import {LinkExternalIcon} from '@primer/octicons-react'
import {Button, PageHeader, ToggleSwitch} from '@primer/react'
import type React from 'react'

interface PageHeaderProps {
  pageTitle: string
  docsUrl?: string
  toggleErrorState?: (isErrorState: boolean) => void
}

const ExampleHeader: React.FC<PageHeaderProps> = ({pageTitle, docsUrl, toggleErrorState}) => {
  return (
    <PageHeader>
      <PageHeader.TitleArea>
        <PageHeader.Title>{pageTitle}</PageHeader.Title>
      </PageHeader.TitleArea>
      <PageHeader.Actions>
        {toggleErrorState && (
          <>
            <span id="toggle-label" style={{fontSize: '14px', fontWeight: 'bold'}}>
              Show Error State?
            </span>
            <ToggleSwitch aria-labelledby="toggle-label" size="small" onChange={toggleErrorState} />
          </>
        )}
        {docsUrl && (
          <Button
            as="a"
            href={docsUrl}
            target="_blank"
            rel="noreferrer"
            variant="primary"
            trailingVisual={LinkExternalIcon}
          >
            Recipe Docs
          </Button>
        )}
      </PageHeader.Actions>
    </PageHeader>
  )
}

export default ExampleHeader

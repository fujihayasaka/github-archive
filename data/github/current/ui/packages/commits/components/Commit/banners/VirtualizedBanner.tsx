import {Banner} from '@primer/react/experimental'
import {useState} from 'react'

export function VirtualizedBanner() {
  const [isDismissed, setIsDismissed] = useState(false)
  return (
    <div className={isDismissed ? '' : 'pt-4'}>
      {!isDismissed && (
        <Banner
          title="Some content is hidden"
          description={
            <div className={'d-flex flex-items-center'} style={{justifyContent: 'center'}}>
              Large Commits have some content hidden by default. Use the searchbox below for content that may be hidden.
            </div>
          }
          variant="warning"
          onDismiss={() => setIsDismissed(true)}
        />
      )}
    </div>
  )
}

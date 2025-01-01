import {clsx} from 'clsx'
import {Button, Link, Spinner} from '@primer/react'
import styles from './HiddenDiffPatch.module.css'
import {useCallback, useState} from 'react'
import {AlertIcon} from '@primer/octicons-react'

type DiffPatchStates = 'loading' | 'initial' | 'error'

function HiddenDiffPatch({
  children,
  helpText,
  helpUrl,
  onLoadDiff,
  diffAnchor,
}: React.PropsWithChildren<{
  helpText?: string
  helpUrl?: string
  onLoadDiff: () => void
  diffAnchor: string
}>) {
  const showLink = helpUrl && helpText
  const [loadingState, setLoadingState] = useState<DiffPatchStates>('initial')
  const onLoadDiffClick = useCallback(async () => {
    try {
      setLoadingState('loading')
      await onLoadDiff()
    } catch {
      setLoadingState('error')
    }
  }, [onLoadDiff, setLoadingState])
  return (
    <div className="px-3 py-4 fgColor-muted" data-diff-anchor={diffAnchor}>
      <div className={clsx(styles.gridColumnTemplate)}>
        <svg
          aria-hidden
          height="84"
          style={{maxWidth: '340px'}}
          viewBox="0 0 340 84"
          xmlns="http://www.w3.org/2000/svg"
        >
          <path
            clipPath="url(#diff-placeholder)"
            d="M0 0h340v84H0z"
            fillRule="evenodd"
            style={{fill: 'var(--bgColor-muted, var(--color-canvas-subtle))'}}
          />
        </svg>{' '}
        <div className="d-flex flex-justify-center flex-column flex-column text-center flex-items-center">
          {loadingState === 'loading' && <Spinner size="medium" />}
          {loadingState === 'error' && <AlertIcon size={24} />}
          {loadingState === 'initial' && (
            <Button
              className="h4 mx-auto fgColor-accent"
              variant={'invisible'}
              onClick={() => {
                onLoadDiffClick()
                setLoadingState('loading')
              }}
            >
              Load Diff
            </Button>
          )}
          {loadingState === 'error' ? (
            <span className="fgColor-muted mt-1">
              The contents of the file couldn&apos;t be loaded.{' '}
              <Link
                inline
                as="button"
                onClick={() => {
                  onLoadDiffClick()
                  setLoadingState('loading')
                }}
              >
                Retry
              </Link>
            </span>
          ) : (
            <span className="fgColor-muted mt-1">
              {children}
              {showLink && (
                <Link inline href={helpUrl}>
                  {helpText}
                </Link>
              )}
            </span>
          )}
        </div>
      </div>
    </div>
  )
}

export default HiddenDiffPatch

import {RefSelector, type RefType} from '@github-ui/ref-selector'
import {useRef, useState} from 'react'

export interface RefSelectorPartialProps {
  ariaDescribedBy?: string
  ariaLabelledBy?: string
  ariaLabel?: string
  buttonClassName?: string
  cacheKey: string | null
  canCreate: boolean
  className?: string
  closeOnSelect?: boolean
  defaultBranch: string | null
  dispatchEvent?: boolean
  formData?: {
    id: string
    name: string
    autosubmit: boolean
  }
  initialRef: string | null
  ownerLogin: string | null
  repoName: string | null
  types: RefType[]
}

export function RefSelectorPartial({
  ariaDescribedBy,
  ariaLabelledBy,
  ariaLabel,
  buttonClassName,
  cacheKey,
  canCreate,
  className,
  closeOnSelect = true,
  defaultBranch,
  dispatchEvent,
  formData,
  initialRef,
  ownerLogin,
  repoName,
  types,
}: RefSelectorPartialProps) {
  const [selectedRef, setSelectedRef] = useState(initialRef ?? defaultBranch ?? '')
  const shouldShowDisabledDefaultBranchPicker = ownerLogin === null || cacheKey === null || defaultBranch === null
  const partialRef = useRef<HTMLDivElement>(null)

  const onSelectItem = (item: string) => {
    setSelectedRef(item)

    if (dispatchEvent) {
      // Request an animation frame to ensure event is dispatched after the value of the hidden input is updated
      window.requestAnimationFrame(() => {
        if (partialRef.current) {
          partialRef.current.dispatchEvent(
            new CustomEvent('ref-selector-partial:change', {
              bubbles: true,
              detail: {refName: item, autosubmit: formData?.autosubmit},
            }),
          )
        }
      })
    }
  }

  return (
    <div className={className} data-testid="ref-selector-partial-container" ref={partialRef}>
      {formData && (
        <input
          type="hidden"
          name={formData.name}
          id={formData.id}
          value={selectedRef}
          data-testid="ref-selector-partial-hidden-input"
        />
      )}
      {shouldShowDisabledDefaultBranchPicker && (
        <div className="d-flex">
          <div className="pt-2 d-none" id="explanation-disabled-button">
            Pick a repository first.
          </div>
          <button className="btn d-flex text-eft text-normal mt-1 ml-2" disabled>
            <span>Default Branch</span>
            <span className="dropdown-caret float-right mt-2" />{' '}
          </button>
        </div>
      )}
      {!shouldShowDisabledDefaultBranchPicker && (
        //passing in empty string for the optional params to make linters happy
        //but the scenario won't happpen in practice
        <RefSelector
          ariaDescribedBy={ariaDescribedBy}
          ariaLabelledBy={ariaLabelledBy}
          ariaLabel={ariaLabel}
          cacheKey={cacheKey ?? ''}
          canCreate={canCreate}
          buttonClassName={buttonClassName}
          closeOnSelect={closeOnSelect}
          currentCommitish={selectedRef}
          defaultBranch={defaultBranch ?? ''}
          onSelectItem={onSelectItem}
          owner={ownerLogin ?? ''}
          repo={repoName ?? ''}
          types={types}
          useFocusZone
        />
      )}
    </div>
  )
}

import {Filter, type SuppliedFilterProvider, ValidationMessage} from '@github-ui/filter'
import {Dialog} from '@primer/react'
import {type RefObject, useState} from 'react'

interface PickerHeaderContentProps {
  inputLabel: string
  inputRef?: RefObject<HTMLInputElement>
  initialQuery?: string
  dialogTitle: string
  dialogLabelId: string
  dialogDescription?: string
  dialogDescriptionId: string
  onDismiss: () => void
  onQueryExecuted: (query: string) => void
  onQueryChange?: (query: string) => void
  providers: SuppliedFilterProvider[]
  extraValidationMessages?: string[]
}

export function PickerHeaderContent({
  dialogTitle,
  dialogLabelId,
  dialogDescription,
  dialogDescriptionId,
  initialQuery = '',
  onDismiss,
  onQueryChange,
  onQueryExecuted,
  inputLabel,
  inputRef,
  providers,
  extraValidationMessages,
}: PickerHeaderContentProps) {
  const [filterValidationMessages, setFilterValidationMessages] = useState<string[]>([])
  const allValidationMessages = [...(extraValidationMessages || []), ...filterValidationMessages]

  return (
    <div className="p-2 border-bottom">
      <div className="d-flex px-2">
        <div className="d-flex flex-1 pt-2">
          <Dialog.Title id={dialogLabelId}>{dialogTitle}</Dialog.Title>
        </div>
        <Dialog.CloseButton onClose={() => onDismiss()} />
      </div>
      <div className="sr-only" id={dialogDescriptionId}>
        {dialogDescription}
      </div>
      <div className="p-2">
        <Filter
          className={allValidationMessages.length ? 'mb-2' : undefined}
          id="picker-filter"
          inputRef={inputRef}
          onChange={onQueryChange}
          initialFilterValue={initialQuery}
          label={inputLabel}
          variant="input"
          onSubmit={({raw}) => onQueryExecuted(raw)}
          providers={providers}
          onValidation={setFilterValidationMessages}
          showValidationMessage={false}
        />

        <ValidationMessage messages={allValidationMessages} id="picker-filter-validation-message" />
      </div>
    </div>
  )
}

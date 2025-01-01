import type {FC} from 'react'
import type React from 'react'
import {useCallback, useId, useState} from 'react'
import {ActionMenu, ActionList, type ActionMenuProps} from '@primer/react'
import type {ActionProps} from '../ActionProps'

type Props = Partial<ActionMenuProps> & {
  options: string[]
  defaultOption: string
  open?: boolean /// Whether the dropdown starts open
  disabled?: boolean /// Whether the dropdown is disabled
  onChange?: (option: string) => void /// Callback when selection is changed
  optionOverride?: (option: string) => React.ReactNode /// Custom option rendering override
} & ActionProps

const SingleSelect: FC<Props> = ({options, defaultOption, onChange, optionOverride, disabled, open, ...rest}) => {
  const [selectedOption, setSelected] = useState<number>(() => options.indexOf(defaultOption))

  const onSelectOption = useCallback(
    (idx: number) => {
      setSelected(idx)
      onChange?.(options[idx]!)
    },
    [options, onChange, setSelected],
  )

  const optionList = options.map((option, index) => (
    <ActionList.Item
      // eslint-disable-next-line @eslint-react/no-array-index-key
      key={index}
      selected={selectedOption === index}
      onSelect={() => {
        onSelectOption(index)
      }}
    >
      {optionOverride ? optionOverride(option) : option}
    </ActionList.Item>
  ))

  const {id: buttonId, 'aria-labelledby': ariaLabelledBy, 'aria-describedby': ariaDescribedBy, ...menuProps} = rest
  const fallbackButtonId = useId()
  const id = buttonId ?? fallbackButtonId
  const buttonProps: ActionProps = {
    id,
    'aria-labelledby': ariaLabelledBy?.includes(id) ? ariaLabelledBy : `${ariaLabelledBy} ${id}`,
    'aria-describedby': ariaDescribedBy,
  }

  return (
    <ActionMenu open={open} {...menuProps}>
      <ActionMenu.Button size={'small'} disabled={disabled} {...buttonProps}>
        {options[selectedOption] ?? defaultOption}
      </ActionMenu.Button>
      <ActionMenu.Overlay>
        <>{optionList.length > 0 && <ActionList selectionVariant="single">{optionList}</ActionList>}</>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}

export default SingleSelect

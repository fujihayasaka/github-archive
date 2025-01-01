import {SearchDropdown, type SearchDropdownItem, type SearchDropdownProps} from '@github-ui/search-dropdown'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useEffect, useState} from 'react'

export interface GitIgnoreDropdownProps
  extends Pick<
    SearchDropdownProps,
    'buttonLabel' | 'buttonSx' | 'buttonClassName' | 'allowNoneOption' | 'textInputProps'
  > {
  selectedTemplate?: string
  onSelect: (templateName: string) => void
  onOpen?: () => void
}

export function GitIgnoreDropdown({
  selectedTemplate,
  buttonLabel,
  buttonSx,
  buttonClassName,
  onSelect,
  allowNoneOption = false,
  onOpen,
}: GitIgnoreDropdownProps) {
  const [templates, setTemplates] = useState<string[] | null>([])

  useEffect(() => {
    const getItems = async () => {
      const response = await verifiedFetchJSON('/site/gitignore/templates')
      if (!response.ok) {
        setTemplates(null)
        return
      }
      try {
        setTemplates(await response.json())
      } catch {
        setTemplates(null)
      }
    }
    getItems()
  }, [])

  const selectableItems: SearchDropdownItem[] = templates?.map(template => ({text: template, id: template})) || []

  return (
    <SearchDropdown
      title=".gitignore template"
      inputLabel="Template filter"
      buttonLabel={buttonLabel}
      // eslint-disable-next-line @github-ui/github-monorepo/no-sx
      buttonSx={buttonSx}
      buttonClassName={buttonClassName}
      selectedItem={selectableItems.find(item => item.id === selectedTemplate)}
      onSelect={item => onSelect(item.id)}
      items={selectableItems}
      allowNoneOption={allowNoneOption}
      onOpen={onOpen}
    />
  )
}

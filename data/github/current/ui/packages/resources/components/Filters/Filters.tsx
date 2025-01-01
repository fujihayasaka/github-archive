import {Stack, Box, Heading, CheckboxGroup, FormControl, Checkbox, Button, InlineLink} from '@primer/react-brand'
import styles from './Filters.module.css'
import {useEffect, useRef, useState} from 'react'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'
import {FilterIcon, XIcon} from '@primer/octicons-react'

export type CheckboxProps = {
  label: string
  value?: string
  isChecked?: boolean
}

export type CheckboxGroupProps = {
  name: string
  label: string
  checkboxes: CheckboxProps[]
}

type FiltersProps = {
  checkboxGroups: CheckboxGroupProps[]
}

export function Filters({checkboxGroups}: FiltersProps) {
  const countInitialFilters = (groups: CheckboxGroupProps[]): number => {
    return groups.reduce((total, group) => {
      const checkedCount = group.checkboxes.filter(checkbox => checkbox.isChecked).length
      return total + checkedCount
    }, 0)
  }

  const initialfiltersCount = countInitialFilters(checkboxGroups)
  const [filtersCount, setFiltersCount] = useState<number>(initialfiltersCount)
  const [narrowMenuOpen, setNarrowMenuOpen] = useState(false)
  const [formDirty, setFormDirty] = useState(false)
  const filtersContainerRef = useRef<HTMLDivElement>(null)

  const onFormChanged = (event: React.ChangeEvent<HTMLFormElement>) => {
    const formElement = event.currentTarget
    const formData = new FormData(formElement)
    setFiltersCount(countSelectedFilters(formData))
    setFormDirty(isFormDirty(formData))
  }

  const onSubmit = (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    const formElement = event.currentTarget
    const formData = new FormData(formElement)

    // Check to see if form values have changed from their initial state. If not, do not update the URL.
    if (!isFormDirty(formData)) return

    const url = new URL(window.location.href, window.location.origin)
    // Remove the page from query params. Since we are changing the filters so we want to start from page 1.
    url.searchParams.delete('page')
    const newSearchParams = new URLSearchParams()

    for (const checkboxGroup of checkboxGroups) {
      // Remove the query param if it exists
      url.searchParams.delete(checkboxGroup.name)

      const selectedValues = formData.getAll(checkboxGroup.name) as string[]

      // Add the selected values to the search params
      if (selectedValues.length > 0) {
        newSearchParams.set(checkboxGroup.name, selectedValues.join(','))
      }
    }

    // Add any other query params that may be present back in to the end of the search params
    for (const [key, value] of url.searchParams.entries()) {
      newSearchParams.set(key, value)
    }

    window.location.href = `${url.origin}${url.pathname}?${newSearchParams.toString()}`
  }

  const isFormDirty = (formData: FormData): boolean => {
    for (const checkboxGroup of checkboxGroups) {
      const selectedValues = formData.getAll(checkboxGroup.name) as string[]

      // Check if this group has changed compared to its initial state
      const hasChanged =
        selectedValues.length !== checkboxGroup.checkboxes.filter(cb => cb.isChecked).length ||
        selectedValues.some(value => !checkboxGroup.checkboxes.find(cb => cb.value === value)?.isChecked)

      if (hasChanged) {
        return true
      }
    }
    return false
  }

  const countSelectedFilters = (formData: FormData): number => {
    let checkedCount = 0

    for (const [, value] of formData.entries()) {
      // Check if the value exists (checkboxes only appear in FormData if they are checked)
      if (value) {
        checkedCount++
      }
    }

    return checkedCount
  }

  const clearAllFilters = () => {
    const url = new URL(window.location.href, window.location.origin)
    url.searchParams.delete('page')
    for (const checkboxGroup of checkboxGroups) {
      url.searchParams.delete(checkboxGroup.name)
    }
    window.location.href = url.href
  }

  const handleNarrowMenu = () => {
    setNarrowMenuOpen(!narrowMenuOpen)
  }

  useEffect(() => {
    // Close menu on "Escape" key for accessibility
    const handleEscape = (event: KeyboardEvent) => {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (event.key === 'Escape') {
        setNarrowMenuOpen(false)
      }
    }

    if (narrowMenuOpen) {
      window.addEventListener('keydown', handleEscape)
    }

    return () => window.removeEventListener('keydown', handleEscape)
  }, [narrowMenuOpen])

  return (
    <div ref={filtersContainerRef}>
      <aside className={styles.aside}>
        <Stack direction="vertical" padding="none" gap="none" className={styles.asideContent}>
          <Stack
            direction="horizontal"
            padding="none"
            justifyContent="space-between"
            alignItems="center"
            className={`${styles.asideHeadingContainer} ${narrowMenuOpen ? styles['asideHeadingContainer--open'] : ''}`}
          >
            <Heading
              as="h2"
              size="subhead-medium"
              font="monospace"
              className={styles.asideHeading}
              weight="medium"
              id="filters-heading"
              data-testid="filters-heading"
            >
              Filters {filtersCount > 0 ? `(${filtersCount})` : ''}
            </Heading>
            <button
              {...getAnalyticsEvent({
                action: `${narrowMenuOpen ? 'collapse' : 'expand'}_filters_menu`,
                tag: 'icon',
                context: 'menu_toggle',
                location: 'filters',
              })}
              data-ref="whitepaper-filters-menu-toggle"
              className={styles.filtersMenuToggle}
              onClick={handleNarrowMenu}
            >
              <span className="sr-only">{narrowMenuOpen ? 'Close' : 'Open'} Filters</span>
              {narrowMenuOpen ? <XIcon size={24} /> : <FilterIcon size={24} />}
            </button>
          </Stack>
          <form noValidate onSubmit={onSubmit} onChange={onFormChanged}>
            <Stack
              direction="vertical"
              padding="none"
              gap={40}
              className={narrowMenuOpen ? '' : styles.filtersStackCollapsed}
            >
              {checkboxGroups.map(checkboxGroup => (
                <Box key={checkboxGroup.name} borderBlockStartWidth="thin" borderColor="subtle" borderStyle="solid">
                  <Box paddingBlockStart={12} paddingBlockEnd={24}>
                    <Heading
                      as="h2"
                      size="subhead-medium"
                      font="monospace"
                      className={styles.navListHeading}
                      weight="medium"
                      stretch="expanded"
                    >
                      {checkboxGroup.label}
                    </Heading>
                  </Box>
                  <Stack direction="vertical" padding="none" gap={12}>
                    <CheckboxGroup>
                      <CheckboxGroup.Label visuallyHidden>{checkboxGroup.label}</CheckboxGroup.Label>
                      {checkboxGroup.checkboxes.map(checkbox => (
                        <FormControl key={`${checkboxGroup.name}-${checkbox.label}`}>
                          <FormControl.Label className={styles.filterLabel}>{checkbox.label}</FormControl.Label>
                          <Checkbox
                            value={checkbox.value}
                            name={checkboxGroup.name}
                            defaultChecked={checkbox.isChecked}
                          />
                        </FormControl>
                      ))}
                    </CheckboxGroup>
                  </Stack>
                </Box>
              ))}
              <Stack direction="horizontal" padding="none" justifyContent="space-between" alignItems="center">
                <InlineLink
                  role="button"
                  aria-disabled={filtersCount === 0}
                  className={`${styles.clearAllLink} ${filtersCount === 0 ? styles['clearAllLink--disabled'] : ''}`}
                  onClick={clearAllFilters}
                  href="#"
                >
                  Clear all
                </InlineLink>
                <Button type="submit" variant="primary" size="small" disabled={!formDirty}>
                  Apply
                </Button>
              </Stack>
            </Stack>
          </form>
        </Stack>
      </aside>
    </div>
  )
}

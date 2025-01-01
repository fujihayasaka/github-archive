import {useCallback, useMemo, useState} from 'react'
import {Button, SelectPanel, type ButtonProps} from '@primer/react'
import {OrganizationIcon, TriangleDownIcon} from '@primer/octicons-react'
import {debounce} from '@github/mini-throttle'
import {GitHubAvatar} from '@github-ui/github-avatar'

export type BaseOrganization = {
  name: string
  primaryAvatarUrl?: string
}

function alreadySelected(name: string, selection: BaseOrganization[] | BaseOrganization | undefined) {
  if (!selection) {
    return false
  }
  if (Array.isArray(selection)) {
    return selection.some(({name: matchingName}) => matchingName === name)
  } else {
    return selection.name === name
  }
}

interface SharedProps<T> {
  buttonText?: string
  additionalButtonProps?: Partial<ButtonProps>
  selectOrg: (org: T) => void
  removeOrg: (org: T) => void
  orgLoader: (q: string) => Promise<T[]>
}

export interface MutliOrgSelectorProps<T> extends SharedProps<T> {
  selectionVariant: 'multiple'
  selection: T[]
}

export interface SingleOrgSelectorProps<T> extends SharedProps<T> {
  selectionVariant: 'single'
  selection: T | undefined
}

export function OrgSelector<T extends BaseOrganization>({
  buttonText,
  additionalButtonProps,
  selectionVariant,
  selection,
  selectOrg,
  removeOrg,
  orgLoader,
}: SingleOrgSelectorProps<T> | MutliOrgSelectorProps<T>) {
  const [suggestions, setSuggestions] = useState<T[]>([])
  const suggestionItems = useMemo(() => {
    const mappedSuggestions = suggestions.map(s => ({
      text: s.name,
      id: s.name,
      leadingVisual: () => s.primaryAvatarUrl && <GitHubAvatar alt={s.name} src={s.primaryAvatarUrl} />,
      onAction: () => {
        const orgToRemove = Array.isArray(selection)
          ? selection.find(({name: matchingName}) => matchingName === s.name)
          : selection && selection.name === s.name
            ? selection
            : undefined
        if (orgToRemove) {
          removeOrg(orgToRemove)
        } else {
          selectOrg(s)
        }
      },
    }))
    return mappedSuggestions
  }, [suggestions, selection, removeOrg, selectOrg])
  const [isLoading, setIsLoading] = useState(false)
  const [open, setOpen] = useState(false)
  const [filter, setFilter] = useState('')

  const onOpen = async () => {
    if (!open) {
      setOpen(true)
      setIsLoading(true)
      setSuggestions(await orgLoader(''))
      setIsLoading(false)
    } else {
      setOpen(false)
    }
  }

  // eslint-disable-next-line react-compiler/react-compiler
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const debounceOrgSuggestions = useCallback(
    debounce(async (newFilter: string) => {
      if (newFilter === '') {
        setSuggestions(await orgLoader(''))
      } else {
        setSuggestions(await orgLoader(newFilter))
      }
    }, 200),
    [orgLoader, setSuggestions],
  )

  const buttonTextOrDefault = useMemo(() => {
    if (buttonText) {
      return buttonText
    } else if (selection === undefined || (Array.isArray(selection) && selection.length === 0)) {
      return `Select organization${selectionVariant === 'multiple' ? 's' : ''}`
    } else {
      if (selectionVariant === 'multiple') {
        return `${selection.length} organization${selection.length === 1 ? '' : 's'} selected`
      } else {
        return selection.name
      }
    }
  }, [buttonText, selection, selectionVariant])

  return (
    <SelectPanel
      loading={isLoading}
      title={`Select organization${selectionVariant === 'multiple' ? 's' : ''}`}
      renderAnchor={({'aria-labelledby': ariaLabelledBy, ...anchorProps}) => (
        <Button
          leadingVisual={OrganizationIcon}
          trailingAction={TriangleDownIcon}
          aria-labelledby={` ${ariaLabelledBy}`}
          {...additionalButtonProps}
          {...anchorProps}
          aria-haspopup="dialog"
        >
          {buttonTextOrDefault}
        </Button>
      )}
      open={open}
      onOpenChange={onOpen}
      items={suggestionItems}
      selected={suggestionItems.filter(item => {
        if (typeof item.id === 'string') {
          return alreadySelected(item.id, selection)
        }
      })}
      /* This is a no-op because we fetch org suggestions from the server as the user types.
       We instead handle this with each item's onAction prop. */
      onSelectedChange={() => {}}
      placeholderText={`Filter organization${selectionVariant === 'multiple' ? 's' : ''}`}
      filterValue={filter}
      onFilterChange={f => {
        setFilter(f)
        debounceOrgSuggestions(f)
      }}
      overlayProps={{
        width: 'medium',
        height: 'medium',
      }}
    />
  )
}

export function simpleOrgLoader<T extends BaseOrganization>(orgs: T[]): (q: string) => Promise<T[]> {
  return async (q: string) => {
    const trimmedFilterText = q.trim().toLowerCase()

    if (!trimmedFilterText) {
      return orgs
    }

    return orgs.filter(
      org => org.name.toLowerCase().includes(trimmedFilterText) || org.name.toLowerCase().includes(trimmedFilterText),
    )
  }
}

import {TriangleDownIcon} from '@primer/octicons-react'
import {ActionList, Button, FormControl, SelectPanel} from '@primer/react'
import type {ActionListItemInput} from '@primer/react/deprecated'
import type React from 'react'
import {useEffect, useMemo, useState} from 'react'

import type {ThemeVariables} from '../../targeted-edits/query'
import styles from './ThemePresetPicker.module.css'
import {ThemeSwatch} from './ThemeSwatch'
import type {ThemePreset} from './utils/presets'
import {presets} from './utils/presets'

interface PresetPickerProps {
  value?: ThemePreset | undefined
  onChange?: (preset: ThemePreset) => void
  themeVariables?: ThemeVariables
}

function SwatchesPreview({colors}: {colors: string[]}) {
  return (
    <span className={styles.triggerSwatches}>
      {colors.map((color, index) => (
        <ThemeSwatch key={color + index} color={color} size="small" />
      ))}
    </span>
  )
}

const matchPresetWithVariables = (variables: Record<string, string> = {}) => {
  for (const preset of Object.values(presets)) {
    const lightStyles = preset.styles.light
    if (
      variables['accent'] === lightStyles.accent &&
      variables['accent-foreground'] === lightStyles['accent-foreground'] &&
      variables['background'] === lightStyles.background &&
      variables['border'] === lightStyles.border &&
      variables['card'] === lightStyles.card &&
      variables['card-foreground'] === lightStyles['card-foreground'] &&
      variables['destructive'] === lightStyles.destructive &&
      variables['destructive-foreground'] === lightStyles['destructive-foreground'] &&
      variables['foreground'] === lightStyles.foreground &&
      variables['input'] === lightStyles.input &&
      variables['muted'] === lightStyles.muted &&
      variables['muted-foreground'] === lightStyles['muted-foreground'] &&
      variables['popover'] === lightStyles.popover &&
      variables['popover-foreground'] === lightStyles['popover-foreground'] &&
      variables['primary'] === lightStyles.primary &&
      variables['primary-foreground'] === lightStyles['primary-foreground'] &&
      variables['ring'] === lightStyles.ring &&
      variables['secondary'] === lightStyles.secondary &&
      variables['secondary-foreground'] === lightStyles['secondary-foreground']
    ) {
      return preset
    }
  }

  return null
}

export function ThemePresetPicker({onChange, themeVariables}: PresetPickerProps) {
  const [open, setOpen] = useState(false)

  const [value, setValue] = useState<ActionListItemInput | undefined>(undefined)
  const [filter, setFilter] = useState('')

  useEffect(() => {
    if (themeVariables) {
      const matchedPreset = matchPresetWithVariables(themeVariables)
      if (matchedPreset) {
        setValue({
          value: matchedPreset.label,
          text: matchedPreset.label,
          ...matchedPreset,
        } as ActionListItemInput)
        // onChange?.(matchedPreset)
      } else {
        setValue(undefined)
      }
    }
  }, [themeVariables])

  const filteredPresets = useMemo(() => {
    return Object.entries(presets)
      .filter(([key]) => {
        return key.toLowerCase().includes(filter.toLowerCase())
      })
      .map(([key, preset]) => ({
        value: key,
        text: preset.label,
        ...preset,
      }))
  }, [filter])

  const handleSelect = (item: ActionListItemInput | undefined) => {
    if (item) {
      setValue(item)
      onChange?.(item as ThemePreset)
      setFilter('')
    }
  }

  const triggerSwatches = useMemo(() => {
    if (value) {
      const colors = (value as ThemePreset).styles.light
      return [colors.accent, colors.primary, colors.secondary, colors.background]
    }

    if (themeVariables) {
      return [
        themeVariables['accent'],
        themeVariables['primary'],
        themeVariables['secondary'],
        themeVariables['background'],
      ].filter(Boolean)
    }

    return null
  }, [value, themeVariables])

  return (
    <FormControl>
      <FormControl.Label visuallyHidden>Theme</FormControl.Label>
      <SelectPanel
        renderAnchor={({children, ...anchorProps}) => (
          <Button
            {...anchorProps}
            variant="invisible"
            block
            size="large"
            trailingAction={TriangleDownIcon}
            aria-haspopup="dialog"
            alignContent="start"
            leadingVisual={triggerSwatches ? <SwatchesPreview colors={triggerSwatches} /> : undefined}
          >
            {children}
          </Button>
        )}
        overlayProps={{
          maxHeight: 'large',
          width: 'auto',
        }}
        placeholder="Custom theme"
        open={open}
        onOpenChange={setOpen}
        items={filteredPresets}
        selected={value}
        onSelectedChange={handleSelect}
        filterValue={filter}
        title="Select a theme"
        placeholderText="Filter themes"
        onFilterChange={setFilter}
        className={styles.selectPanel}
        message={
          filteredPresets.length === 0 && filter
            ? {
                title: 'No themes found',
                body: 'Try changing the filter or selecting a different theme.',
                variant: 'empty',
              }
            : undefined
        }
        renderItem={item => {
          const itemTheme = item as ThemePreset
          const isSelected = value ? (value as ThemePreset).label === itemTheme.label : false
          return (
            <ActionList.Item
              {...item}
              id={itemTheme.label}
              onSelect={(e: React.MouseEvent<HTMLElement> | React.KeyboardEvent<HTMLElement>) => {
                item.onAction?.(item, e as React.MouseEvent<HTMLDivElement> | React.KeyboardEvent<HTMLDivElement>)
              }}
              selected={isSelected}
            >
              <ActionList.LeadingVisual>
                <SwatchesPreview
                  colors={[
                    itemTheme.styles.light.accent,
                    itemTheme.styles.light.primary,
                    itemTheme.styles.light.secondary,
                    itemTheme.styles.light.background,
                  ]}
                />
              </ActionList.LeadingVisual>
              {itemTheme.label}
            </ActionList.Item>
          )
        }}
      />
    </FormControl>
  )
}

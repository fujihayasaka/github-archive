import {CheckCircleFillIcon, CircleIcon} from '@primer/octicons-react'
import {AnchoredOverlay, Box, Button, IconButton, Text} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {useCallback, useState} from 'react'
import {graphql, useFragment} from 'react-relay'
import styles from './IconAndColorPicker.module.css'

import {
  SUPPORTED_VIEW_COLORS,
  VIEW_COLOR_BACKGROUND_MAP,
  VIEW_COLOR_FOREGROUND_MAP,
  VIEW_COLOR_LABELS,
} from '../../sidebar/ColorHelper'
import {CUSTOM_VIEW_ICONS_TO_PRIMER_ICON, customViewIconToPrimerIcon} from '../../sidebar/IconHelper'
import type {IconAndColorPickerViewFragment$key} from './__generated__/IconAndColorPickerViewFragment.graphql'
import {BUTTON_LABELS} from '../../../constants/buttons'
import {LABELS} from '../../../constants/labels'
import {useQueryContext, useQueryEditContext} from '../../../contexts/QueryContext'
import {VALUES} from '../../../constants/values'
import {announce} from '@github-ui/aria-live'

type Props = {
  readOnly: boolean
  currentView: IconAndColorPickerViewFragment$key
}

export function IconAndColorPicker({readOnly, currentView}: Props) {
  const {isEditing, isNewView} = useQueryContext()

  const {icon: viewIcon, color: viewColor} = useFragment<IconAndColorPickerViewFragment$key>(
    graphql`
      fragment IconAndColorPickerViewFragment on Shortcutable {
        icon
        color
      }
    `,
    currentView,
  )

  const {dirtyViewIcon, setDirtyViewIcon, dirtyViewColor, setDirtyViewColor} = useQueryEditContext()

  const onSetOpen = useCallback((isOpen: boolean) => {
    setIsOpen(isOpen)
  }, [])

  const [isOpen, setIsOpen] = useState(false)

  const onSave = useCallback(() => {
    onSetOpen(false)
  }, [onSetOpen])

  const onIconSelection = useCallback(
    (newIcon: string) => {
      setDirtyViewIcon(newIcon)
      announce(`${newIcon} selected`)
    },
    [setDirtyViewIcon],
  )

  const onColorSelection = useCallback(
    (newColor: string) => {
      setDirtyViewColor(newColor)
      announce(`${newColor} selected`)
    },
    [setDirtyViewColor],
  )

  const onCancel = useCallback(() => {
    onSetOpen(false)
    setDirtyViewIcon(null)
    setDirtyViewColor(null)
  }, [onSetOpen, setDirtyViewIcon, setDirtyViewColor])

  const selectedIconName = dirtyViewIcon || (isNewView ? VALUES.defaultViewIcon : viewIcon)
  const selectedViewColor = dirtyViewColor || (isNewView ? VALUES.defaultViewColor : viewColor)
  const selectedIcon = customViewIconToPrimerIcon(selectedIconName)
  const selectedBackgroundColor = VIEW_COLOR_BACKGROUND_MAP[selectedViewColor]
  const selectedForegroundColor = VIEW_COLOR_FOREGROUND_MAP[selectedViewColor]

  return readOnly || !isEditing ? (
    <Box
      sx={{
        backgroundColor: selectedBackgroundColor,
        color: selectedForegroundColor,
        borderRadius: 2,
        width: 32,
        height: 32,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
      }}
    >
      <Octicon icon={customViewIconToPrimerIcon(viewIcon)!} />
    </Box>
  ) : (
    <AnchoredOverlay
      renderAnchor={anchorProps => (
        <div {...anchorProps}>
          <IconButton
            {...anchorProps}
            aria-labelledby={undefined}
            aria-label={LABELS.views.iconAndColorAnchorAriaLabel}
            icon={selectedIcon!}
            size="medium"
            variant="invisible"
            onClick={() => onSetOpen(!isOpen)}
            id="edit-view-icon-button"
            sx={{
              backgroundColor: selectedBackgroundColor,
              color: selectedForegroundColor,
            }}
          />
        </div>
      )}
      focusZoneSettings={{disabled: true}}
      focusTrapSettings={{restoreFocusOnCleanUp: true}}
      open={isOpen}
      onOpen={() => onSetOpen(true)}
      onClose={onCancel}
      className={styles.anchoredOverlay}
    >
      <Box sx={{mb: 2, mt: 2, p: 1, maxWidth: 420}}>
        <Text sx={{ml: 2, fontWeight: 'bold', color: 'fg.muted'}}>{LABELS.views.color}</Text>
        <Box sx={{display: 'flex', flexDirection: 'row', flexWrap: 'wrap', alignItems: 'start', p: 2, gap: 2}}>
          {SUPPORTED_VIEW_COLORS.map(color => {
            const fgColor = VIEW_COLOR_FOREGROUND_MAP[color]
            const bgColor = VIEW_COLOR_BACKGROUND_MAP[color]

            return (
              <IconButton
                key={color}
                icon={color === selectedViewColor ? CheckCircleFillIcon : CircleIcon}
                aria-label={VIEW_COLOR_LABELS[color] ?? color}
                variant="invisible"
                sx={{
                  '&:hover:not([aria-disabled])': {
                    backgroundColor: color === selectedViewColor ? fgColor : bgColor,
                    color: color === selectedViewColor ? 'fg.onEmphasis' : fgColor,
                  },
                  backgroundColor: color === selectedViewColor ? fgColor : 'transparent',
                  svg: {
                    color: color === selectedViewColor ? 'fg.onEmphasis' : fgColor,
                  },
                }}
                onClick={() => onColorSelection(color)}
              />
            )
          })}
        </Box>
        <Text sx={{ml: 2, fontWeight: 'bold', color: 'fg.muted'}}>{LABELS.views.icon}</Text>
        <Box sx={{display: 'flex', flexDirection: 'row', flexWrap: 'wrap', alignItems: 'start', pl: 2, pt: 2, gap: 2}}>
          {Object.keys(CUSTOM_VIEW_ICONS_TO_PRIMER_ICON).map(icon => (
            // eslint-disable-next-line primer-react/a11y-remove-disable-tooltip
            <IconButton
              unsafeDisableTooltip
              key={icon}
              icon={customViewIconToPrimerIcon(icon)!}
              aria-label={icon}
              variant="invisible"
              sx={{
                '&:hover:not([aria-disabled])': {
                  backgroundColor: selectedBackgroundColor,
                  svg: {color: selectedForegroundColor},
                },
                '&:focus:not([aria-disabled])': {
                  backgroundColor: icon === selectedIconName ? selectedForegroundColor : 'transparent',
                  svg: {color: icon === selectedIconName ? 'fg.onEmphasis' : selectedForegroundColor},
                },
                backgroundColor: icon === selectedIconName ? selectedForegroundColor : 'transparent',
                svg: {
                  color: icon === selectedIconName ? 'fg.onEmphasis' : 'fg.muted',
                },
              }}
              onClick={() => onIconSelection(icon)}
            />
          ))}
        </Box>
        <Box sx={{pr: 2, gap: 2, pt: 2, flexDirection: 'row', display: 'flex', justifyContent: 'end'}}>
          <Button onClick={onCancel}>{BUTTON_LABELS.cancel}</Button>
          <Button variant="primary" onClick={onSave}>
            {BUTTON_LABELS.apply}
          </Button>
        </Box>
      </Box>
    </AnchoredOverlay>
  )
}

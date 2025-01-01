import {SearchIcon} from '@primer/octicons-react'
import {AnchoredOverlay, TextInput} from '@primer/react'
import {useMemo, useState} from 'react'

import {useReadOnly} from '../../contexts/ReadOnlyContext'
import styles from './ColorPickerItem.module.css'
import {colors} from './utils/colors'

interface ColorPickerItemProps {
  token: 'background' | 'foreground'
  label: string
  activeColor: string
  onChange: (key: string, value: string) => void
}

export function ColorPickerItem(props: ColorPickerItemProps) {
  const {activeColor, onChange, token} = props
  const readOnly = useReadOnly()

  const [open, setOpen] = useState(false)
  const [searchTerm, setSearchTerm] = useState('')

  const activeValue = useMemo(() => {
    for (const [key, c] of Object.entries(colors)) {
      for (const [step, colorValue] of Object.entries(c)) {
        if (
          activeColor === colorValue ||
          activeColor === `bg-${key}-${step}` ||
          activeColor === `text-${key}-${step}`
        ) {
          return colorValue
        }
      }
    }

    return activeColor
  }, [activeColor])

  const filteredColors = useMemo(() => {
    if (!searchTerm) return colors

    const searchLower = searchTerm.toLowerCase()
    return Object.fromEntries(Object.entries(colors).filter(([key]) => key.toLowerCase().includes(searchLower)))
  }, [searchTerm])

  return (
    <AnchoredOverlay
      open={open}
      onOpen={() => setOpen(true)}
      onClose={() => {
        setOpen(false)
        setSearchTerm('')
      }}
      renderAnchor={anchorProps => (
        <button {...anchorProps} className={styles.trigger} disabled={readOnly} aria-label="Color picker">
          <span className="sr-only">{props.label}</span>
          <span
            className={styles.triggerColor}
            style={{backgroundColor: activeValue}}
            data-empty={activeValue === ''}
          />
        </button>
      )}
    >
      <div className={styles.pickerContainer}>
        <TextInput
          leadingVisual={SearchIcon}
          value={searchTerm}
          onChange={e => setSearchTerm(e.target.value)}
          placeholder="Search colors..."
        />
        {Object.entries(filteredColors).map(([key, color]) => {
          return (
            <div key={key} className={styles.colorContainer}>
              <div className={styles.sectionHeading}>{key}</div>
              <div className={styles.colorList}>
                {Object.entries(color).map(([step, value]) => {
                  const selected =
                    activeColor === value ||
                    activeColor === `bg-${key}-${step}` ||
                    activeColor === `text-${key}-${step}`

                  return (
                    <button
                      key={key + step}
                      className={styles.colorItem}
                      onClick={() => {
                        onChange(token === 'foreground' ? `text-${key}-${step}` : `bg-${key}-${step}`, value)
                        setOpen(false)
                      }}
                      aria-label={value}
                      data-selected={selected}
                      style={{
                        '--color': value,
                      }}
                    />
                  )
                })}
              </div>
            </div>
          )
        })}
      </div>
    </AnchoredOverlay>
  )
}

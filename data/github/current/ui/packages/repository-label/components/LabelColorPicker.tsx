import {forwardRef, useState} from 'react'
import {SyncIcon} from '@primer/octicons-react'
import styles from './LabelColorPicker.module.css'
import {FormControl, IconButton, TextInput, Button} from '@primer/react'
import {useLabelStyles} from '@github-ui/use-label-styles'

const DARK_COLORS = ['#b60205', '#d93f0b', '#fbca04', '#0e8a16', '#006b75', '#1d76db', '#0052cc', '#5319e7']
const LIGHT_COLORS = ['#e99695', '#f9d0c4', '#fef2c0', '#c2e0c6', '#bfdadc', '#c5def5', '#bfd4f2', '#d4c5f9']

type LabelColorPickerProps = {
  color: string
  onChangeCallback?: (color: string) => void
}

export function randomHexColor(): string {
  const randomChannel = () => Math.floor(Math.random() * 256)
  return `#${[randomChannel(), randomChannel(), randomChannel()].map(c => c.toString(16).padStart(2, '0')).join('')}`
}

export function isValidColor(color: string): boolean {
  return /^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6})$/.test(color)
}

export const LabelColorPicker = forwardRef<HTMLInputElement, LabelColorPickerProps>(
  ({color, onChangeCallback}, inputRef) => {
    const [currentInputValue, setCurrentInputValue] = useState(color)
    const [currentColor, setCurrentColor] = useState(color)
    const [showPopup, setShowPopup] = useState(false)
    const labelStyles = useLabelStyles(1, currentColor)

    const handleColorChange = (newColor: string) => {
      setCurrentInputValue(newColor)

      // Validate the color input
      if (isValidColor(newColor)) {
        setCurrentColor(newColor)
      }

      onChangeCallback?.(newColor)
    }

    const handleRandomColor = () => handleColorChange(randomHexColor())

    const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => handleColorChange(e.target.value)

    const handleColorSelect = (selectedColor: string) => {
      handleColorChange(selectedColor)
      setShowPopup(false)
    }

    const colorButton = (c: string, i: number) => (
      <Button
        variant="invisible"
        key={i}
        className={styles.color}
        style={{backgroundColor: c}}
        aria-label={c}
        onClick={() => {
          handleColorSelect(c)
        }}
        tabIndex={0}
      />
    )

    return (
      <FormControl>
        <FormControl.Label>Color</FormControl.Label>
        <div className={styles.container}>
          <IconButton
            style={{...labelStyles, backgroundColor: currentColor}}
            icon={SyncIcon}
            aria-label="Choose random color"
            title="Choose random color"
            onClick={handleRandomColor}
          />
          <div className={styles.inputContainer}>
            <FormControl>
              <FormControl.Label visuallyHidden>Color</FormControl.Label>
              <TextInput
                value={currentInputValue}
                onChange={handleInputChange}
                onFocus={() => setShowPopup(true)}
                onBlur={e => {
                  if (!e.relatedTarget || !e.relatedTarget.closest(`.${styles.popup}`)) {
                    setShowPopup(false)
                  }
                }}
                validationStatus={isValidColor(currentInputValue) ? 'success' : 'error'}
                ref={inputRef}
              />
            </FormControl>
            {showPopup && (
              <div
                className={styles.popup}
                tabIndex={-1} // Make the popup focusable to allow `relatedTarget` to work
              >
                <span className={styles.text}>Choose from default colors</span>
                <div className={styles.colors}>{DARK_COLORS.map(colorButton)}</div>
                <div className={styles.colors}>{LIGHT_COLORS.map(colorButton)}</div>
              </div>
            )}
          </div>
        </div>
      </FormControl>
    )
  },
)

LabelColorPicker.displayName = 'LabelColorPicker'

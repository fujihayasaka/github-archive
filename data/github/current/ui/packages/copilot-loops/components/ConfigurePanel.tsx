import {useState, type ChangeEvent} from 'react'
import {ActionList, ActionMenu, FormControl, TextInput, Textarea} from '@primer/react'
import styles from './ConfigurePanel.module.css'
import {useUpdateLoopMutation} from '../hooks/mutations/use-update-loop-mutation'
import {useLoop} from '../hooks/queries/use-loop'
import {Icon, type IconColor} from '@github-ui/pacer/Icon'
import {availableColors, pickColorBasedOnString} from '../utils/color'

// Helper function to capitalize the first letter
const capitalizeFirstLetter = (string: string): string => {
  return string.charAt(0).toUpperCase() + string.slice(1)
}

export function ConfigurePanel() {
  const updateLoop = useUpdateLoopMutation()
  const {data: loop} = useLoop()

  // put this is state so it doesn't change if the user types a new name
  const [randomColor] = useState(() => (loop?.title ? pickColorBasedOnString(loop?.title, availableColors) : 'blue'))

  const handleNameChange = (e: ChangeEvent<HTMLInputElement>) => {
    if (!loop) return
    const newName = e.target.value

    updateLoop.mutate({
      loopID: loop.id,
      updateFn: existingLoop => {
        if (!existingLoop) return loop

        return {
          ...existingLoop,
          title: newName,
        }
      },
    })
  }

  const handleDescriptionChange = (e: ChangeEvent<HTMLTextAreaElement>) => {
    if (!loop) return
    const newDescription = e.target.value

    updateLoop.mutate({
      loopID: loop.id,
      updateFn: existingLoop => {
        if (!existingLoop) return loop

        return {
          ...existingLoop,
          description: newDescription,
        }
      },
    })
  }

  const handleColorChange = (color: IconColor) => {
    if (!loop) return

    updateLoop.mutate({
      loopID: loop.id,
      updateFn: existingLoop => {
        if (!existingLoop) return loop

        return {
          ...existingLoop,
          color,
        }
      },
    })
  }

  if (!loop) return null

  const {title, color: loopColor, description} = loop
  const color = loopColor || randomColor

  return (
    <div className={styles.container}>
      <FormControl className={styles.nameForm}>
        <FormControl.Label>Name</FormControl.Label>
        <TextInput block value={title} onChange={handleNameChange} placeholder="Loop name" />
        <FormControl.Caption>Memorable name that helps you find your loop.</FormControl.Caption>
      </FormControl>

      <div className={styles.iconSection}>
        <div className={styles.iconView}>
          <Icon color={color} hasBackground icon="loops" size={24} />
        </div>
        <FormControl className={styles.iconForm}>
          <FormControl.Label>Icon</FormControl.Label>
          <FormControl.Caption>Pick a color to easier recognize your loop.</FormControl.Caption>
          <ActionMenu>
            <ActionMenu.Button variant="default">
              <span className={styles.iconColorLabel}>Color: </span>
              <span>{capitalizeFirstLetter(color)}</span>
            </ActionMenu.Button>
            <ActionMenu.Overlay>
              <ActionList selectionVariant="single">
                {availableColors.map(colorOption => (
                  <ActionList.Item
                    key={colorOption}
                    onSelect={() => handleColorChange(colorOption)}
                    selected={color === colorOption}
                  >
                    {capitalizeFirstLetter(colorOption)}
                  </ActionList.Item>
                ))}
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        </FormControl>
      </div>

      <FormControl className={styles.descriptionForm}>
        <FormControl.Label>Description</FormControl.Label>
        <div className={styles.descriptionInput}>
          <Textarea
            block
            value={description || ''}
            onChange={handleDescriptionChange}
            rows={4}
            maxLength={200}
            resize="vertical"
            placeholder="Describe what this loop does"
          />
          <div className={styles.descriptionCounter}>
            <span>{description?.length ?? 0}</span> / 200
          </div>
        </div>
        <FormControl.Caption>
          Shows beneath the title on your loop overview page and does not impact responses.
        </FormControl.Caption>
      </FormControl>
    </div>
  )
}

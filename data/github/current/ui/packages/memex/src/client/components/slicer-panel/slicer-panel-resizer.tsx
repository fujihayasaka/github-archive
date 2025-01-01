import {
  type Coordinates,
  DndContext,
  type DndContextProps,
  type KeyboardCoordinateGetter,
  KeyboardSensor,
  type KeyboardSensorOptions,
  MouseSensor,
  useDraggable,
  useSensor,
  useSensors,
} from '@github-ui/drag-and-drop'
import {testIdProps} from '@github-ui/test-id-props'
import {Box} from '@primer/react'
import {useCallback, useState} from 'react'

import useBodyClass from '../../hooks/use-body-class'
import {SLICER_PANEL_DEFAULT_WIDTH, SLICER_PANEL_MAX_WIDTH, SLICER_PANEL_MIN_WIDTH} from './constants'

type SlicerPanelResizerControlProps = {
  /** The current width of the panel */
  width: number
  /** Event handler for reset size event, called when the resizer control is double clicked */
  onResetSize: () => void
}

const SlicerPanelResizerSash = ({width, onResetSize}: SlicerPanelResizerControlProps) => {
  const sashId = 'slicer-panel-resizer-sash'
  const {
    attributes: {role, ...attributes},
    listeners,
    setNodeRef,
    isDragging,
  } = useDraggable({
    id: sashId,
    attributes: {
      role: 'separator',
    },
  })

  useBodyClass('is-resizing-slicer-panel', isDragging)

  return (
    <Box
      ref={setNodeRef}
      sx={{
        bg: isDragging ? 'accent.fg' : 'border.default',
        cursor: 'col-resize',
        position: 'relative',
        transitionDelay: '0.1s',
        width: '1px',
        outline: 'none', // This is to remove focus outline when dragCancel is triggered
        zIndex: 10,
      }}
      aria-valuenow={width}
      aria-valuemin={SLICER_PANEL_MIN_WIDTH}
      aria-valuemax={SLICER_PANEL_MAX_WIDTH}
      aria-orientation="vertical"
      id={sashId}
      role={role}
      {...attributes}
      {...testIdProps('slicer-panel-resizer-sash')}
      tabIndex={-1}
    >
      <Box
        {...listeners}
        sx={{
          cursor: 'col-resize',
          inset: '0 -3px',
          position: 'absolute',
          height: '100%',
        }}
        {...testIdProps('slicer-panel-resizer-sash-drag-activator')}
        tabIndex={0}
        onDoubleClick={onResetSize}
      />
    </Box>
  )
}

type SlicerPanelResizerProps = {
  /** Handler for resize event, called while resize handle is dragging, used to update width of panel locally */
  onResize: (width: number) => void
  /** Handler for resize end event, called when dragging has stopped, been cancelled, or when size is reset,
   * called with final width and used for updating the server state
   */
  onResizeEnd: (width: number) => void
  /** The current width of the slicer panel */
  width: number
}

export const SlicerPanelResizer = ({onResize, onResizeEnd, width}: SlicerPanelResizerProps) => {
  const [originalWidth, setOriginalWidth] = useState(width)

  const handleDragStart = () => {
    setOriginalWidth(width)
  }

  // DndKit defaults to PointerEvent(s), however, there is no good way to narrow this further
  const handleDragMove: DndContextProps['onDragMove'] = ({delta, active}) => {
    const initialActiveRect = active.rect.current.initial
    if (!initialActiveRect) return

    const initialLeft = Math.floor(initialActiveRect.left + initialActiveRect.width / 2)
    let newWidth = initialLeft + delta.x

    if (newWidth > SLICER_PANEL_MAX_WIDTH) {
      newWidth = SLICER_PANEL_MAX_WIDTH
    }

    if (newWidth < SLICER_PANEL_MIN_WIDTH) {
      newWidth = SLICER_PANEL_MIN_WIDTH
    }

    onResize(Math.round(newWidth))
  }

  const handleDragEnd = () => {
    handleResizeEnd(width)
  }

  const handleDragCancel = () => {
    onResize(originalWidth)
  }

  const handleResetSize = () => {
    handleResizeEnd(SLICER_PANEL_DEFAULT_WIDTH)
  }

  const handleResizeEnd = (newWidth: number) => {
    // If the width hasn't changed, don't call the onResizeEnd callback, this is to prevent
    // unnecessary calls to the server when the user is just clicking/double-clicking on the resizer sash
    if (newWidth === originalWidth) return
    onResizeEnd(newWidth)
  }

  // This is a custom coordinate getter for the keyboard sensor, it allows us to use all the arrow keys to resize
  // the panel (Up/Right to move expand it, Down/Left to decrease the size)
  const coordinatesGetter: KeyboardCoordinateGetter = useCallback(
    (
      event: KeyboardEvent,
      args: {
        currentCoordinates: Coordinates
      },
    ) => {
      const {currentCoordinates} = args
      const delta = 25
      const coordinates = {...currentCoordinates}
      switch (event.code) {
        case 'ArrowDown':
          coordinates.x = coordinates.x - delta
          break
        case 'ArrowUp':
          coordinates.x = coordinates.x + delta
          break
        case 'ArrowRight':
          coordinates.x = coordinates.x + delta
          break
        case 'ArrowLeft':
          coordinates.x = coordinates.x - delta
          break
        case 'Tab':
          // Prevent the browser from changing the focus
          event.preventDefault()
          break
        default:
          return undefined
      }

      return coordinates
    },
    [],
  )

  const sensors = useSensors(
    useSensor(MouseSensor),
    useSensor<KeyboardSensorOptions>(KeyboardSensor, {
      coordinateGetter: coordinatesGetter,
    }),
  )

  return (
    <DndContext
      autoScroll={false}
      onDragCancel={handleDragCancel}
      onDragEnd={handleDragEnd}
      onDragMove={handleDragMove}
      onDragStart={handleDragStart}
      accessibility={{
        screenReaderInstructions: {
          draggable: 'Press enter/space to resize pane with arrow keys. Press escape to exit.',
        },
      }}
      sensors={sensors}
    >
      <SlicerPanelResizerSash onResetSize={handleResetSize} width={width} />
    </DndContext>
  )
}

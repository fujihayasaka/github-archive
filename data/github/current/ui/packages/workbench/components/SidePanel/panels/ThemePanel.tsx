import {Button, SegmentedControl} from '@primer/react'
import {useEffect, useRef, useState} from 'react'

import {useFileSyncerContext} from '../../../contexts/FileSyncerContext'
import {ReadOnlyProvider} from '../../../contexts/ReadOnlyContext'
import {useTargetedEditsContext} from '../../../contexts/TargetedEditsContext'
import {Region, useRegionState} from '../../../hooks/use-region-state'
import {ColorPickerItem} from '../ColorPickerItem'
import {Overscroll} from '../Overscroll'
import {Section} from '../Section'
import {ThemePresetPicker} from '../ThemePresetPicker'
import type {ThemePreset} from '../utils/presets'

const CSS_FILE_PATH = 'src/index.css'

export function ThemePanel() {
  const {modifyGlobalCssVariable, modifyThemeVariables, themeVariables, refetchThemeVariables} =
    useTargetedEditsContext()

  const {fileChangeStack} = useFileSyncerContext()

  const panelState = useRegionState(Region.THEME)

  const scrollRef = useRef<HTMLDivElement>(null)
  const [showAllColors, setShowAllColors] = useState(false)

  const readOnly = panelState === 'readOnly'

  const handleThemeChange = (newTheme: ThemePreset) => {
    modifyThemeVariables({
      updates: Object.entries(newTheme.styles.light).map(([key, value]) => ({
        name: key,
        value,
      })),
    })
  }

  useEffect(() => {
    refetchThemeVariables()
  }, [refetchThemeVariables])

  useEffect(() => {
    for (const change of fileChangeStack) {
      if (change.path === CSS_FILE_PATH) {
        refetchThemeVariables()
      }
    }
  }, [fileChangeStack, refetchThemeVariables])

  if (!themeVariables) {
    return null
  }

  return (
    <ReadOnlyProvider readOnly={readOnly}>
      <div className="position-relative mt-3">
        <Overscroll scrollingRef={scrollRef} />
        <div ref={scrollRef} style={{margin: 'calc(var(--base-size-16, 16px) * -1)'}}>
          <div className="px-2 py-2 border-bottom borderColor-muted">
            <ThemePresetPicker onChange={handleThemeChange} themeVariables={themeVariables} />
          </div>

          <Section title="Color" variant="bordered">
            <Section.GroupLabels label1="Background" label2="Text" />
            <Section.Group label="Accent">
              <ColorPickerItem
                token="background"
                label="Background"
                activeColor={themeVariables['accent']}
                onChange={(_key, color) => {
                  modifyGlobalCssVariable({name: 'accent', value: color})
                }}
              />
              <ColorPickerItem
                token="foreground"
                label="Text"
                activeColor={themeVariables['accent-foreground']}
                onChange={(_key, color) => {
                  modifyGlobalCssVariable({name: 'accent-foreground', value: color})
                }}
              />
            </Section.Group>
            <Section.Group label="Primary">
              <ColorPickerItem
                token="background"
                label="Background"
                activeColor={themeVariables['primary']}
                onChange={(_key, color) => {
                  modifyGlobalCssVariable({name: 'primary', value: color})
                }}
              />
              <ColorPickerItem
                token="foreground"
                label="Text"
                activeColor={themeVariables['primary-foreground']}
                onChange={(_key, color) => {
                  modifyGlobalCssVariable({name: 'primary-foreground', value: color})
                }}
              />
            </Section.Group>
            <Section.Group label="Secondary">
              <ColorPickerItem
                token="background"
                label="Background"
                activeColor={themeVariables['secondary']}
                onChange={(_key, color) => {
                  modifyGlobalCssVariable({name: 'secondary', value: color})
                }}
              />
              <ColorPickerItem
                token="foreground"
                label="Text"
                activeColor={themeVariables['secondary-foreground']}
                onChange={(_key, color) => {
                  modifyGlobalCssVariable({name: 'secondary-foreground', value: color})
                }}
              />
            </Section.Group>
            <Section.Group label="Base">
              <ColorPickerItem
                token="background"
                label="Background"
                activeColor={themeVariables['background']}
                onChange={(_key, color) => {
                  modifyGlobalCssVariable({name: 'background', value: color})
                }}
              />
              <ColorPickerItem
                token="foreground"
                label="Text"
                activeColor={themeVariables['foreground']}
                onChange={(_key, color) => {
                  modifyGlobalCssVariable({name: 'foreground', value: color})
                }}
              />
            </Section.Group>
            {showAllColors && (
              <>
                <Section.Group label="Muted">
                  <ColorPickerItem
                    token="background"
                    label="Background"
                    activeColor={themeVariables['muted']}
                    onChange={(_key, color) => {
                      modifyGlobalCssVariable({name: 'muted', value: color})
                    }}
                  />
                  <ColorPickerItem
                    token="foreground"
                    label="Text"
                    activeColor={themeVariables['muted-foreground']}
                    onChange={(_key, color) => {
                      modifyGlobalCssVariable({name: 'muted-foreground', value: color})
                    }}
                  />
                </Section.Group>
                <Section.Group label="Destructive">
                  <ColorPickerItem
                    token="background"
                    label="Background"
                    activeColor={themeVariables['destructive']}
                    onChange={(_key, color) => {
                      modifyGlobalCssVariable({name: 'destructive', value: color})
                    }}
                  />
                  <ColorPickerItem
                    token="foreground"
                    label="Text"
                    activeColor={themeVariables['destructive-foreground']}
                    onChange={(_key, color) => {
                      modifyGlobalCssVariable({name: 'destructive-foreground', value: color})
                    }}
                  />
                </Section.Group>
                <Section.Group label="Card">
                  <ColorPickerItem
                    token="background"
                    label="Background"
                    activeColor={themeVariables['card']}
                    onChange={(_key, color) => {
                      modifyGlobalCssVariable({name: 'card', value: color})
                    }}
                  />
                  <ColorPickerItem
                    token="foreground"
                    label="Text"
                    activeColor={themeVariables['card-foreground']}
                    onChange={(_key, color) => {
                      modifyGlobalCssVariable({name: 'card-foreground', value: color})
                    }}
                  />
                </Section.Group>
                <Section.Group label="Popover">
                  <ColorPickerItem
                    token="background"
                    label="Background"
                    activeColor={themeVariables['popover']}
                    onChange={(_key, color) => {
                      modifyGlobalCssVariable({name: 'popover', value: color})
                    }}
                  />
                  <ColorPickerItem
                    token="foreground"
                    label="Text"
                    activeColor={themeVariables['popover-foreground']}
                    onChange={(_key, color) => {
                      modifyGlobalCssVariable({name: 'popover-foreground', value: color})
                    }}
                  />
                </Section.Group>
                <Section.Group label="Input">
                  <ColorPickerItem
                    token="background"
                    label="Background"
                    activeColor={themeVariables['input']}
                    onChange={(_key, color) => {
                      modifyGlobalCssVariable({name: 'input', value: color})
                    }}
                  />
                </Section.Group>
                <Section.Group label="Border">
                  <ColorPickerItem
                    token="background"
                    label="Background"
                    activeColor={themeVariables['border']}
                    onChange={(_key, color) => {
                      modifyGlobalCssVariable({name: 'border', value: color})
                    }}
                  />
                </Section.Group>
                <Section.Group label="Ring">
                  <ColorPickerItem
                    token="background"
                    label="Background"
                    activeColor={themeVariables['ring']}
                    onChange={(_key, color) => {
                      modifyGlobalCssVariable({name: 'ring', value: color})
                    }}
                  />
                </Section.Group>
              </>
            )}
            <div className="pt-2">
              <Button
                block
                onClick={() => {
                  setShowAllColors(s => !s)
                }}
              >
                {showAllColors ? 'Hide colors' : 'Show all colors'}
              </Button>
            </div>
          </Section>

          <Section title="Appearance" variant="bordered">
            <Section.Group label="Border radius" columns={1}>
              <div>
                <SegmentedControl aria-label="Border radius">
                  <SegmentedControl.IconButton
                    disabled={readOnly}
                    aria-label="None"
                    icon={BorderRadiusNoneIcon}
                    selected={themeVariables['radius'] === 'none'}
                    onClick={() => {
                      modifyGlobalCssVariable({name: 'radius', value: '0'})
                    }}
                  />
                  <SegmentedControl.IconButton
                    disabled={readOnly}
                    aria-label="Small"
                    icon={BorderRadiusSmallIcon}
                    selected={themeVariables['radius'] === 'small'}
                    onClick={() => {
                      modifyGlobalCssVariable({name: 'radius', value: '0.3rem'})
                    }}
                  />
                  <SegmentedControl.IconButton
                    disabled={readOnly}
                    aria-label="Medium"
                    icon={BorderRadiusMediumIcon}
                    selected={themeVariables['radius'] === 'medium'}
                    onClick={() => {
                      modifyGlobalCssVariable({name: 'radius', value: '0.5rem'})
                    }}
                  />
                  <SegmentedControl.IconButton
                    disabled={readOnly}
                    aria-label="Large"
                    icon={BorderRadiusLargeIcon}
                    selected={themeVariables['radius'] === 'large'}
                    onClick={() => {
                      modifyGlobalCssVariable({name: 'radius', value: '0.75rem'})
                    }}
                  />
                  <SegmentedControl.IconButton
                    disabled={readOnly}
                    aria-label="Full"
                    icon={BorderRadiusFullIcon}
                    selected={themeVariables['radius'] === 'full'}
                    onClick={() => {
                      modifyGlobalCssVariable({name: 'radius', value: '1rem'})
                    }}
                  />
                </SegmentedControl>
              </div>
            </Section.Group>
            <Section.Group label="Spacing" columns={1}>
              <div>
                <SegmentedControl aria-label="Spacing">
                  <SegmentedControl.IconButton
                    disabled={readOnly}
                    aria-label="None"
                    icon={SpacingSmallIcon}
                    selected={themeVariables['spacing'] === 'none'}
                    onClick={() => {
                      modifyGlobalCssVariable({name: 'spacing', value: '0.20rem'})
                    }}
                  />
                  <SegmentedControl.IconButton
                    disabled={readOnly}
                    aria-label="Small"
                    icon={SpacingMediumIcon}
                    selected={themeVariables['spacing'] === 'small'}
                    onClick={() => {
                      modifyGlobalCssVariable({name: 'spacing', value: '0.25rem'})
                    }}
                  />
                  <SegmentedControl.IconButton
                    disabled={readOnly}
                    aria-label="Medium"
                    icon={SpacingLargeIcon}
                    selected={themeVariables['spacing'] === 'medium'}
                    onClick={() => {
                      modifyGlobalCssVariable({name: 'spacing', value: '0.3rem'})
                    }}
                  />
                </SegmentedControl>
              </div>
            </Section.Group>
          </Section>
        </div>
      </div>
    </ReadOnlyProvider>
  )
}

const BorderRadiusNoneIcon = (props: React.ComponentProps<'svg'>) => {
  return (
    <svg
      {...props}
      width={16}
      height={16}
      viewBox="0 0 16 16"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden="true"
      className="octicon"
    >
      <path
        d="M3.25 12.5V3.25H12.5C12.9142 3.25 13.25 3.58579 13.25 4C13.25 4.41421 12.9142 4.75 12.5 4.75H4.75V12.5C4.75 12.9142 4.41421 13.25 4 13.25C3.58579 13.25 3.25 12.9142 3.25 12.5Z"
        fill="currentColor"
      />
    </svg>
  )
}

const BorderRadiusSmallIcon = (props: React.ComponentProps<'svg'>) => {
  return (
    <svg
      {...props}
      aria-hidden="true"
      viewBox="0 0 16 16"
      width={16}
      height={16}
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className="octicon"
    >
      <path
        d="M3.25 12.5V5C3.25 4.0335 4.0335 3.25 5 3.25H12.5C12.9142 3.25 13.25 3.58579 13.25 4C13.25 4.41421 12.9142 4.75 12.5 4.75H5C4.86193 4.75 4.75 4.86193 4.75 5V12.5C4.75 12.9142 4.41421 13.25 4 13.25C3.58579 13.25 3.25 12.9142 3.25 12.5Z"
        fill="currentColor"
      />
    </svg>
  )
}

const BorderRadiusMediumIcon = (props: React.ComponentProps<'svg'>) => {
  return (
    <svg
      {...props}
      aria-hidden="true"
      viewBox="0 0 16 16"
      width={16}
      height={16}
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className="octicon"
    >
      <path
        d="M3.25 12.5V7C3.25 4.92893 4.92893 3.25 7 3.25H12.5C12.9142 3.25 13.25 3.58579 13.25 4C13.25 4.41421 12.9142 4.75 12.5 4.75H7C5.75736 4.75 4.75 5.75736 4.75 7V12.5C4.75 12.9142 4.41421 13.25 4 13.25C3.58579 13.25 3.25 12.9142 3.25 12.5Z"
        fill="currentColor"
      />
    </svg>
  )
}

const BorderRadiusLargeIcon = (props: React.ComponentProps<'svg'>) => {
  return (
    <svg
      {...props}
      aria-hidden="true"
      viewBox="0 0 16 16"
      width={16}
      height={16}
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className="octicon"
    >
      <path
        d="M3.25 12.5V9C3.25 5.82436 5.82436 3.25 9 3.25H12.5C12.9142 3.25 13.25 3.58579 13.25 4C13.25 4.41421 12.9142 4.75 12.5 4.75H9C6.65279 4.75 4.75 6.65279 4.75 9V12.5C4.75 12.9142 4.41421 13.25 4 13.25C3.58579 13.25 3.25 12.9142 3.25 12.5Z"
        fill="currentColor"
      />
    </svg>
  )
}

const BorderRadiusFullIcon = (props: React.ComponentProps<'svg'>) => {
  return (
    <svg
      {...props}
      aria-hidden="true"
      viewBox="0 0 16 16"
      width={16}
      height={16}
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className="octicon"
    >
      <path
        d="M3.25 12.5V11C3.25 6.71979 6.71979 3.25 11 3.25H12.5C12.9142 3.25 13.25 3.58579 13.25 4C13.25 4.41421 12.9142 4.75 12.5 4.75H11C7.54822 4.75 4.75 7.54822 4.75 11V12.5C4.75 12.9142 4.41421 13.25 4 13.25C3.58579 13.25 3.25 12.9142 3.25 12.5Z"
        fill="currentColor"
      />
    </svg>
  )
}

const SpacingSmallIcon = (props: React.ComponentProps<'svg'>) => {
  return (
    <svg
      {...props}
      aria-hidden
      width={16}
      height={16}
      viewBox="0 0 16 16"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className="octicon"
    >
      <path d="M6 8H10" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      <path d="M2.5 11H13.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      <path d="M13.5 5L2.5 5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  )
}

const SpacingMediumIcon = (props: React.ComponentProps<'svg'>) => {
  return (
    <svg
      {...props}
      aria-hidden
      width={16}
      height={16}
      viewBox="0 0 16 16"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className="octicon"
    >
      <path d="M6 8H10" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      <path d="M2.5 12.5H13.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      <path d="M13.5 3.25L2.5 3.25" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  )
}

const SpacingLargeIcon = (props: React.ComponentProps<'svg'>) => {
  return (
    <svg
      {...props}
      aria-hidden
      width={16}
      height={16}
      viewBox="0 0 16 16"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className="octicon"
    >
      <path d="M6 8H10" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      <path d="M2.5 13.5H13.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      <path d="M13.5 2.25L2.5 2.25" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  )
}

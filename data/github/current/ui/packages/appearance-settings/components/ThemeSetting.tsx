import {ActionList, ActionMenu} from '@primer/react'
import {useCallback, useState, useEffect} from 'react'
import {ControlGroup} from '@github-ui/control-group'
import {ThemeVisual} from './ThemeVisual'
import styles from './ThemeSetting.module.css'

// NOTE this is a prototype and not connected to any business logic

export type ThemeModeValues = 'sync_with_system' | 'light' | 'dark'

export type Themes =
  | 'dark'
  | 'dark_dimmed'
  | 'dark_colorblind'
  | 'dark_tritanopia'
  | 'light'
  | 'light_colorblind'
  | 'light_tritanopia'

export function ThemeSetting() {
  const options: {[key in ThemeModeValues]: {name: string}} = {
    sync_with_system: {name: 'Sync with system'},
    light: {name: 'Light'},
    dark: {name: 'Dark'},
  }

  const [selectedThemeMode, setSelectedThemeMode] = useState<ThemeModeValues>('sync_with_system')
  useEffect(() => {
    setSelectedThemeMode('sync_with_system')
  }, [])

  const themeOptions: {[key in Themes]: {name: string}} = {
    dark: {name: 'Dark'},
    dark_dimmed: {name: 'Dark dimmed'},
    dark_colorblind: {name: 'Dark colorblind'},
    dark_tritanopia: {name: 'Dark tritanopia'},
    light: {name: 'Light'},
    light_colorblind: {name: 'Light colorblind'},
    light_tritanopia: {name: 'Light tritanopia'},
  }

  // for the light menu, set 'light' as the default value
  const [selectedLightTheme, setSelectedLightTheme] = useState<Themes>('light')
  useEffect(() => {
    setSelectedLightTheme('light')
  }, [])
  const [selectedTheme, setSelectedTheme] = useState<Themes>('dark')
  useEffect(() => {
    setSelectedTheme('dark')
  }, [])

  const getLightThemeForVisual = useCallback(() => {
    if (selectedLightTheme.startsWith('light')) {
      return 'light'
    } else if (selectedLightTheme.startsWith('dark_dimmed')) {
      return 'dark_dimmed'
    } else if (selectedLightTheme.startsWith('dark')) {
      return 'dark'
    }
    return 'light' // Default fallback
  }, [selectedLightTheme])

  const LightThemeVisualComponent = <ThemeVisual theme={getLightThemeForVisual()} />

  const getDarkThemeForVisual = useCallback(() => {
    if (selectedTheme.startsWith('light')) {
      return 'light'
    } else if (selectedTheme.startsWith('dark_dimmed')) {
      return 'dark_dimmed'
    } else if (selectedTheme.startsWith('dark')) {
      return 'dark'
    }
    return 'light' // Default fallback
  }, [selectedTheme])

  const ThemeVisualComponent = <ThemeVisual theme={getDarkThemeForVisual()} />

  // if theme mode is set to 'light' hide the dark theme control item

  const isLightMode = selectedThemeMode === 'light'
  const isDarkMode = selectedThemeMode === 'dark'
  const isSyncWithSystem = selectedThemeMode === 'sync_with_system'

  return (
    <ControlGroup>
      <ControlGroup.Item>
        <ControlGroup.Title id="theme-mode-label">Theme mode</ControlGroup.Title>
        <ControlGroup.Description>
          <span id="theme-mode-description">
            Choose a single theme or sync with system for automatic light and dark mode
          </span>
        </ControlGroup.Description>
        <ControlGroup.Custom>
          <ActionMenu>
            <ActionMenu.Button
              id="theme-mode-button"
              aria-labelledby="theme-mode-label theme-mode-button"
              aria-describedby="theme-mode-description"
            >
              {options[selectedThemeMode].name}
            </ActionMenu.Button>
            <ActionMenu.Overlay width="small">
              <ActionList selectionVariant="single">
                {Object.entries(options).map(([key, {name}]) => (
                  <ActionList.Item
                    key={key}
                    selected={selectedThemeMode === key}
                    onSelect={() => {
                      setSelectedThemeMode(key as ThemeModeValues)
                    }}
                  >
                    {name}
                  </ActionList.Item>
                ))}
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        </ControlGroup.Custom>
      </ControlGroup.Item>
      {(isLightMode || isSyncWithSystem) && (
        <ControlGroup.Item nestedLevel={1}>
          <ControlGroup.Title id="light-mode-label">Light mode</ControlGroup.Title>
          <ControlGroup.Custom>
            <ActionMenu>
              <ActionMenu.Button
                id="theme-mode-button"
                aria-labelledby="theme-mode-label theme-mode-button"
                aria-describedby="theme-mode-description"
                leadingVisual={LightThemeVisualComponent}
                className={styles.themePickerButton}
              >
                {themeOptions[selectedLightTheme].name}
              </ActionMenu.Button>
              <ActionMenu.Overlay width="small">
                <ActionList selectionVariant="single">
                  {Object.entries(themeOptions).map(([key, {name}]) => (
                    <ActionList.Item
                      key={key}
                      selected={selectedLightTheme === key}
                      onSelect={() => {
                        setSelectedLightTheme(key as Themes)
                      }}
                    >
                      {name}
                    </ActionList.Item>
                  ))}
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
          </ControlGroup.Custom>
        </ControlGroup.Item>
      )}
      {(isDarkMode || isSyncWithSystem) && (
        <ControlGroup.Item nestedLevel={1}>
          <ControlGroup.Title id="dark-mode-label">Dark mode</ControlGroup.Title>
          <ControlGroup.Custom>
            <ActionMenu>
              <ActionMenu.Button
                id="theme-mode-button"
                aria-labelledby="theme-mode-label theme-mode-button"
                aria-describedby="theme-mode-description"
                leadingVisual={ThemeVisualComponent}
                className={styles.themePickerButton}
              >
                {themeOptions[selectedTheme].name}
              </ActionMenu.Button>
              <ActionMenu.Overlay width="small">
                <ActionList selectionVariant="single">
                  {Object.entries(themeOptions).map(([key, {name}]) => (
                    <ActionList.Item
                      key={key}
                      selected={selectedTheme === key}
                      onSelect={() => {
                        setSelectedTheme(key as Themes)
                      }}
                    >
                      {name}
                    </ActionList.Item>
                  ))}
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
          </ControlGroup.Custom>
        </ControlGroup.Item>
      )}
    </ControlGroup>
  )
}

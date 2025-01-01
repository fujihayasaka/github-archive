import {ActionList, ActionMenu, SegmentedControl} from '@primer/react'
import {useState} from 'react'
import {ControlGroup} from '@github-ui/control-group'

// NOTE this is a prototype and not connected to any business logic

export function PersonalizationSetting() {
  const skintoneEmojis = [
    {emoji: '👋', label: 'Neutral'},
    {emoji: '👋🏻', label: 'Light skin tone'},
    {emoji: '👋🏼', label: 'Medium-light skin tone'},
    {emoji: '👋🏽', label: 'Medium skin tone'},
    {emoji: '👋🏾', label: 'Medium-dark skin tone'},
    {emoji: '👋🏿', label: 'Dark skin tone'},
  ].map(({emoji, label}) => ({element: <span key={emoji}>{emoji}</span>, label}))

  const tabSizeOptions: Record<number, {name: string}> = {
    1: {name: '1 space'},
    2: {name: '2 spaces'},
    3: {name: '3 spaces'},
    4: {name: '4 spaces'},
    5: {name: '5 spaces'},
    6: {name: '6 spaces'},
    8: {name: '8 spaces (default)'},
    10: {name: '10 spaces'},
    12: {name: '12 spaces'},
  }
  const [selectedIndex, setSelectedIndex] = useState(8)
  const selectedType = tabSizeOptions[selectedIndex]

  return (
    <ControlGroup>
      <ControlGroup.Item>
        <ControlGroup.Title id="markdown-toggle">Monospace markdown editor font</ControlGroup.Title>
        <ControlGroup.Description>
          Font for plain text editors that support Markdown styling (e.g. pull request and issue descriptions,
          comments.)
        </ControlGroup.Description>
        <ControlGroup.ToggleSwitch aria-labelledby="markdown-toggle" />
      </ControlGroup.Item>
      <ControlGroup.Item>
        <ControlGroup.Title id="emoji-color-label">Emoji skin tone</ControlGroup.Title>
        <ControlGroup.Description>
          <span id="emoji-color-description">Select your default emoji skin tone</span>
        </ControlGroup.Description>
        <ControlGroup.Custom>
          <SegmentedControl
            size="medium"
            aria-labelledby="emoji-color-label"
            aria-describedby="emoji-color-description"
          >
            {skintoneEmojis.map((emoji, index) => (
              <SegmentedControl.IconButton key={index} icon={emoji.element} aria-label={emoji.label} />
            ))}
          </SegmentedControl>
        </ControlGroup.Custom>
      </ControlGroup.Item>
      <ControlGroup.Item>
        <ControlGroup.Title id="tab-size-label">Tab size</ControlGroup.Title>
        <ControlGroup.Description>
          <span id="tab-size-description">Select the number of spaces a tab is equal to when rendering code</span>
        </ControlGroup.Description>
        <ControlGroup.Custom>
          <ActionMenu>
            <ActionMenu.Button
              id="increase-contrast-button"
              aria-labelledby="tab-size-label increase-contrast-button"
              aria-describedby="tab-size-description"
            >
              {selectedType?.name}
            </ActionMenu.Button>
            <ActionMenu.Overlay width="small">
              <ActionList selectionVariant="single">
                {Object.entries(tabSizeOptions).map(([key, tabSizeOption]) => (
                  <ActionList.Item
                    key={key}
                    selected={Number(key) === selectedIndex}
                    onSelect={() => setSelectedIndex(Number(key))}
                  >
                    {tabSizeOption.name}
                  </ActionList.Item>
                ))}
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        </ControlGroup.Custom>
      </ControlGroup.Item>
    </ControlGroup>
  )
}

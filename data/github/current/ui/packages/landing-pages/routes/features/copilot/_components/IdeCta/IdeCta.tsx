import {ActionMenu, ThemeProvider} from '@primer/react-brand'
import editors from '@github-ui/global-copilot-menu/editors'
import {recordMenuClick} from '@github-ui/global-copilot-menu/EditorMenuItems'

import {AzureDataStudioLogo} from './icons/AzureDataStudioLogo'
import {JetBrainsLogo} from './icons/JetBrainsLogo'
import {NeoVimLogo} from './icons/NeoVimLogo'
import {VisualStudioLogo} from './icons/VisualStudioLogo'
import {VisualStudioCodeLogo} from './icons/VisualStudioCodeLogo'
import {XcodeLogo} from './icons/XcodeLogo'

const editorIcons: Record<keyof typeof editors, JSX.Element> = {
  vscode: <VisualStudioCodeLogo />,
  visualstudio: <VisualStudioLogo />,
  xcode: <XcodeLogo />,
  jetbrains: <JetBrainsLogo />,
  neovim: <NeoVimLogo />,
}

const allEditors = {
  ...Object.fromEntries(
    Object.entries(editors).map(([key, value]) => [
      key,
      {
        name: value.name,
        url: value.url,
        icon: editorIcons[key as keyof typeof editorIcons],
      },
    ]),
  ),
  azure_data_studio: {
    name: 'Azure Data Studio',
    url: 'https://learn.microsoft.com/en-us/azure-data-studio/extensions/github-copilot-extension-overview',
    icon: <AzureDataStudioLogo />,
  },
} as Record<keyof typeof editors | 'azure_data_studio', {name: string; url: string; icon: JSX.Element}>

export type IdeLinks = Partial<Record<keyof typeof allEditors, string>>

type Props = {
  deepLinks?: IdeLinks
}

export default function IdeCta({deepLinks}: Props) {
  return (
    <ThemeProvider colorMode="light" style={{background: 'transparent'}}>
      <ActionMenu mode="split-button">
        <ActionMenu.Button
          variant="subtle"
          as="a"
          href={deepLinks?.vscode || allEditors.vscode.url}
          leadingVisual={allEditors.vscode.icon}
        >
          Install Copilot in Visual Studio Code
        </ActionMenu.Button>

        <ActionMenu.Overlay aria-label="Alternative actions">
          {Object.entries(allEditors).map(([editor, {name, url, icon}]) => {
            const editorUrl = deepLinks?.[editor as keyof IdeLinks] || url
            return (
              <ActionMenu.Item
                key={editor}
                as="a"
                href={editorUrl}
                leadingVisual={icon}
                onClick={() => {
                  recordMenuClick({eventName: editor, menuLocation: 'marketing_ide_cta', text: editorUrl})
                }}
              >
                <span style={{whiteSpace: 'nowrap'}}>{name}</span>
              </ActionMenu.Item>
            )
          })}
        </ActionMenu.Overlay>
      </ActionMenu>
    </ThemeProvider>
  )
}

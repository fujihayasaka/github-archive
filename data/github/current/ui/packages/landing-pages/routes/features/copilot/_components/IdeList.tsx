import IdeItem from './IdeItem'

import GitHubIcon from '../_assets/ide-icons/github.svg'
import VSCodeIcon from '../_assets/ide-icons/vscode.svg'
import VisualStudioIcon from '../_assets/ide-icons/visualstudio.svg'
import XcodeIcon from '../_assets/ide-icons/xcode.svg'
import JetBrainsIcon from '../_assets/ide-icons/jetbrains.svg'
import NeovimIcon from '../_assets/ide-icons/neovim.svg'
import AzureDataStudioIcon from '../_assets/ide-icons/azure.svg'

interface IdeListProps {
  location: string
  type: 'big' | 'small'
}

export default function IdeList({location, type = 'big'}: IdeListProps) {
  const IdeData = [
    {
      title: 'GitHub',
      href: 'https://github.com/copilot',
      image: GitHubIcon,
      action: 'github',
      location,
    },
    {
      title: 'VS Code',
      href: 'https://marketplace.visualstudio.com/items?itemName=GitHub.copilot',
      image: VSCodeIcon,
      action: 'vscode',
      location,
    },
    {
      title: 'Visual Studio',
      href: 'https://visualstudio.microsoft.com/github-copilot',
      image: VisualStudioIcon,
      action: 'vs',
      location,
    },
    {
      title: 'Xcode',
      href: 'https://github.com/github/CopilotForXcode',
      image: XcodeIcon,
      action: 'xcode',
      location,
    },
    {
      title: 'JetBrains',
      appendix: 'IDEs',
      href: 'https://plugins.jetbrains.com/plugin/17718-github-copilot',
      image: JetBrainsIcon,
      action: 'jetbrains',
      location,
    },
    {
      title: 'Neovim',
      href: 'https://github.com/github/copilot.vim',
      image: NeovimIcon,
      action: 'neovim',
      location,
    },
    {
      title: 'Azure',
      appendix: 'Data Studio',
      href: 'https://learn.microsoft.com/en-us/azure-data-studio/extensions/github-copilot-extension-overview',
      image: AzureDataStudioIcon,
      action: 'azuredatastudio',
      location,
    },
  ]

  return (
    <ul className={`lp-IDE-list${type === 'small' ? ' lp-IDE-list--small' : ''}`}>
      {IdeData.map(ide => (
        <IdeItem
          key={ide.action}
          href={ide.href}
          image={ide.image}
          action={ide.action}
          location={ide.location}
          text={ide.title}
          appendix={ide.appendix}
        />
      ))}
    </ul>
  )
}

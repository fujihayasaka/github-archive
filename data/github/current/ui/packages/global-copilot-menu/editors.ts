import azureIcon from './assets/azure.png'
import jetbrainsIcon from './assets/jetbrains.png'
import neovimIcon from './assets/neovim.png'
import vscodeIcon from './assets/vscode.png'
import vsstudioIcon from './assets/vsstudio.png'
import xcodeIcon from './assets/xcode.png'

export default {
  vscode: {
    url: 'https://marketplace.visualstudio.com/items?itemName=GitHub.copilot',
    icon: vscodeIcon,
    name: 'Visual Studio Code',
    eventName: 'VSCODE',
  },
  visualstudio: {
    url: 'https://visualstudio.microsoft.com/github-copilot/',
    icon: vsstudioIcon,
    name: 'Visual Studio',
    eventName: 'VS',
  },
  xcode: {
    url: 'https://github.com/github/CopilotForXcode',
    icon: xcodeIcon,
    name: 'Xcode',
    eventName: 'XCODE',
  },
  jetbrains: {
    url: 'https://plugins.jetbrains.com/plugin/17718-github-copilot',
    icon: jetbrainsIcon,
    name: 'JetBrains',
    eventName: 'JETBRAINS',
  },
  neovim: {
    url: 'https://github.com/github/copilot.vim',
    icon: neovimIcon,
    name: 'Neovim',
    eventName: 'NEOVIM',
  },
  datastudio: {
    url: 'https://learn.microsoft.com/en-us/azure-data-studio/extensions/github-copilot-extension-overview',
    icon: azureIcon,
    name: 'Azure Data Studio',
    eventName: 'AZURE_DATA',
  },
}

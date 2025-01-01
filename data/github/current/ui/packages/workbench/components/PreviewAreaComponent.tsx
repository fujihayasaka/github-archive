import {CodespaceStatusIndicator} from '@github-ui/shared-workspace-components/CodespaceStatusIndicator'
import {useEffect, useRef, useState} from 'react'

import {CommandTask} from '../../workspace-editor/utilities/terminal-reducer'
import type {ConnectedCodespaceData} from '../../workspace-editor/utilities/workspace-editor-types'
import {useTerminalContext} from '../contexts/TerminalContext'

interface PreviewAreaComponentProps {
  codespaceData: ConnectedCodespaceData
}

export const PreviewAreaComponent = ({codespaceData}: PreviewAreaComponentProps) => {
  const ref = useRef<HTMLIFrameElement>(null)
  const codespaceName = codespaceData?.codespaceInfo?.environment_data.friendlyName

  const codespaceDataProps = {
    hasCodespaceInfo: !!codespaceData.codespaceInfo,
    codespaceState: codespaceData?.codespaceState,
    codespaceFriendlyName: codespaceData?.codespaceInfo?.environment_data.friendlyName,
    codespaceSkuDisplayName: codespaceData?.codespaceInfo?.environment_data.skuDisplayName,
    codespacePermissionAccepted: !!codespaceData?.permissionsStatus?.accepted,
    codespaceAllowUrl: codespaceData?.permissionsStatus?.allowPermissionsUrl,
    isCodespaceRecoveryContainer: codespaceData.isRecoveryContainer,
    pollForCodespacePermissionsAccepted: codespaceData.pollForPermissionsAccepted,
    recreateCodespace: codespaceData.recreateCodespace,
    onDetailsClick: () => {},
  }

  const [websiteUrl, setWebsiteUrl] = useState<string | null>(null)
  const {executeCommand} = useTerminalContext()
  useEffect(() => {
    async function waitOnPort() {
      if (codespaceName && codespaceData.codespaceState === 'ready') {
        const result = await executeCommand(`gh cs ports visibility 5000:public -c $CODESPACE_NAME`, CommandTask.Build)
        // eslint-disable-next-line no-console
        console.log(result)
        setWebsiteUrl(`https://${codespaceName}-5000.app.github.dev/`)
      }
    }
    waitOnPort()
  }, [codespaceName, codespaceData.codespaceState, executeCommand])

  if (!codespaceName || codespaceData.codespaceState !== 'ready' || !websiteUrl) {
    return <CodespaceStatusIndicator {...codespaceDataProps} />
  }

  return (
    <div>
      <iframe
        ref={ref}
        src={websiteUrl}
        title="Preview Website"
        style={{width: '100%', height: '100vh', border: 'none'}}
        allow="geolocation; microphone; camera; midi; encrypted-media; clipboard-write; web-share"
        // eslint-disable-next-line @eslint-react/dom/no-unsafe-iframe-sandbox
        sandbox="allow-scripts allow-same-origin allow-forms allow-modals allow-popups allow-presentation"
      />
    </div>
  )
}

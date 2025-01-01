import {useCallback, useMemo, useState} from 'react'
import {useIsPlatform} from '@github-ui/use-is-platform'
import {useNavigate} from '@github-ui/use-navigate'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {ActionList, Box, Flash, Heading, Link, UnderlineNav} from '@primer/react'
import {Tooltip} from '@primer/react/next'
import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {DesktopDownloadIcon, FileZipIcon, QuestionIcon, TerminalIcon} from '@primer/octicons-react'

interface InternalTab {
  protocol: string
  displayName: string
  ariaLabel: string
  handler: () => void
}

interface Platform {
  name: string
  text: string
  url: string
  icon?: React.ComponentType
}

export interface LocalTabProps {
  protocolInfo: {
    httpAvailable: boolean
    sshAvailable: boolean
    httpUrl: string
    showCloneWarning: boolean
    sshUrl: string
    sshCertificatesRequired: boolean
    sshCertificatesAvailable: boolean
    ghCliUrl: string
    defaultProtocol: string
    newSshKeyUrl: string
    setProtocolPath: string
  }
  platformInfo: {
    cloneUrl: string
    visualStudioCloneUrl: string
    xcodeCloneUrl: string
    zipballUrl: string
    showVisualStudioCloneButton: boolean
    showXcodeCloneButton: boolean
  }
  helpUrl: string
}

export function LocalTab(props: LocalTabProps) {
  const {
    httpAvailable,
    sshAvailable,
    httpUrl,
    showCloneWarning,
    sshUrl,
    sshCertificatesRequired,
    sshCertificatesAvailable,
    ghCliUrl,
    newSshKeyUrl,
    setProtocolPath,
  } = props.protocolInfo
  const {defaultProtocol} = props.protocolInfo
  const [activeLocalTab, setActiveLocalTab] = useState(defaultProtocol)
  const [openingPlatform, setOpeningPlatform] = useState('')

  const {cloneUrl, visualStudioCloneUrl, showVisualStudioCloneButton, showXcodeCloneButton, xcodeCloneUrl, zipballUrl} =
    props.platformInfo
  const isMacOrWindows = useIsPlatform(['windows', 'mac'])
  const isMac = useIsPlatform(['mac'])
  const navigate = useNavigate()

  const localProtocolClassName = 'mt-2 fgColor-muted text-normal'

  const onProtocolTabClick = useCallback(
    (protocol: string) => {
      if (activeLocalTab !== protocol) {
        setActiveLocalTab(protocol)
        const formData = new FormData()
        formData.set('protocol_selector', protocol)
        verifiedFetch(setProtocolPath, {method: 'post', body: formData})
      }
    },
    [activeLocalTab, setActiveLocalTab, setProtocolPath],
  )

  const tabs = useMemo(() => {
    const result: InternalTab[] = []
    const handleHttpClick = () => onProtocolTabClick('http')
    const handleSshClick = () => onProtocolTabClick('ssh')
    const handleCliClick = () => onProtocolTabClick('gh_cli')

    if (httpAvailable) {
      result.push({protocol: 'http', displayName: 'HTTPS', ariaLabel: 'Clone with HTTPS', handler: handleHttpClick})
    }

    if (sshAvailable) {
      result.push({protocol: 'ssh', displayName: 'SSH', ariaLabel: 'Clone with SSH', handler: handleSshClick})
    }

    result.push({
      protocol: 'gh_cli',
      displayName: 'GitHub CLI',
      ariaLabel: 'Clone with GitHub CLI',
      handler: handleCliClick,
    })
    return result
  }, [httpAvailable, onProtocolTabClick, sshAvailable])

  const platforms = useMemo(() => {
    const result: Platform[] = []
    if (isMacOrWindows) {
      result.push({name: 'githubDesktop', text: 'Open with GitHub Desktop', url: cloneUrl, icon: DesktopDownloadIcon})
    }
    if (isMacOrWindows && showVisualStudioCloneButton) {
      result.push({name: 'visualStudio', text: 'Open with Visual Studio', url: visualStudioCloneUrl})
    }
    if (isMac && showXcodeCloneButton) {
      result.push({name: 'xcode', text: 'Open with Xcode', url: xcodeCloneUrl})
    }
    result.push({
      name: 'zip',
      text: 'Download ZIP',
      url: zipballUrl,
      icon: FileZipIcon,
    })
    return result
  }, [
    cloneUrl,
    isMac,
    isMacOrWindows,
    showVisualStudioCloneButton,
    showXcodeCloneButton,
    visualStudioCloneUrl,
    xcodeCloneUrl,
    zipballUrl,
  ])

  return (
    <div>
      {openingPlatform === 'githubDesktop' ? (
        <LaunchingPlatformContents platform="GitHub Desktop" href="https://desktop.github.com/" />
      ) : openingPlatform === 'visualStudio' ? (
        <LaunchingPlatformContents platform="Visual Studio" />
      ) : openingPlatform === 'xcode' ? (
        <LaunchingPlatformContents platform="Xcode" href="https://developer.apple.com/xcode/" />
      ) : (
        <>
          <div className="m-3">
            <div className="d-flex flex-items-center">
              <TerminalIcon className="mr-2" />
              <p className="flex-1 text-bold mb-0">Clone</p>
              <Tooltip text="Which remote URL should I use?" type="label" direction="w">
                <Link muted href={`${props.helpUrl}/articles/which-remote-url-should-i-use`}>
                  <QuestionIcon className="mr-1" />
                </Link>
              </Tooltip>
            </div>
            <UnderlineNav sx={{border: 'none', my: 2, px: 0, fontWeight: 'bold'}} aria-label="Remote URL selector">
              {tabs.map(tab => (
                <UnderlineNav.Item
                  key={tab.protocol}
                  aria-current={activeLocalTab === tab.protocol ? 'page' : undefined}
                  aria-label={tab.ariaLabel}
                  onClick={tab.handler}
                >
                  {tab.displayName}
                </UnderlineNav.Item>
              ))}
            </UnderlineNav>
            {activeLocalTab === 'http' ? (
              <>
                <CloneUrl inputId="clone-with-https" inputLabel="Clone with HTTPS url" url={httpUrl} />
                <p className={localProtocolClassName}>Clone using the web URL.</p>
              </>
            ) : activeLocalTab === 'ssh' ? (
              <>
                {showCloneWarning && (
                  <Flash className="mb-2" variant="warning">
                    {"You don't have any public SSH keys in your GitHub account. "}
                    You can{' '}
                    <Link inline href={newSshKeyUrl}>
                      add a new public key
                    </Link>
                    , or try cloning this repository via HTTPS.
                  </Flash>
                )}
                <CloneUrl inputId="clone-with-ssh" inputLabel="Clone with SSH url" url={sshUrl} />
                <p className={localProtocolClassName}>
                  {sshCertificatesRequired
                    ? 'Use a password-protected SSH certificate.'
                    : sshCertificatesAvailable
                      ? 'Use a password-protected SSH key or certificate.'
                      : 'Use a password-protected SSH key.'}
                </p>
              </>
            ) : (
              <>
                <CloneUrl
                  buttonAriaLabel="Copy command to clipboard"
                  inputId="clone-with-gh-cli"
                  inputLabel="Clone with GitHub CLI command"
                  url={ghCliUrl}
                />
                <p className={localProtocolClassName}>
                  Work fast with our official CLI.{' '}
                  <Link
                    inline
                    href="https://cli.github.com"
                    target="_blank"
                    aria-label="Learn more about the GitHub CLI"
                  >
                    Learn more
                  </Link>
                </p>
              </>
            )}
          </div>
          <ActionList variant="inset" className="border-top">
            {platforms.map(platform =>
              platform.name === 'zip' ? (
                <ActionList.LinkItem key={platform.name} data-turbo="false" href={platform.url} rel="nofollow">
                  {platform.icon && (
                    <ActionList.LeadingVisual>
                      <platform.icon />
                    </ActionList.LeadingVisual>
                  )}
                  {platform.text}
                </ActionList.LinkItem>
              ) : (
                <ActionList.Item
                  key={platform.name}
                  onSelect={ev => {
                    setOpeningPlatform(platform.name)
                    ev.preventDefault()
                    navigate(platform.url)
                  }}
                >
                  {platform.icon && (
                    <ActionList.LeadingVisual>
                      <platform.icon />
                    </ActionList.LeadingVisual>
                  )}
                  {platform.text}
                </ActionList.Item>
              ),
            )}
          </ActionList>
        </>
      )}
    </div>
  )
}

function LaunchingPlatformContents({platform, href}: {platform: string; href?: string}) {
  return (
    <Box className="p-3" sx={{width: '400px'}}>
      <Heading as="h4" className="mb-3 text-center">
        {`Launching ${platform}`}
      </Heading>
      {href && (
        <p className="mb-3">
          If nothing happens, <Link inline href={href}>{`download ${platform}`}</Link> and try again.
        </p>
      )}
    </Box>
  )
}

export function CloneUrl({
  buttonAriaLabel = 'Copy url to clipboard',
  inputId,
  inputLabel,
  url,
}: {
  buttonAriaLabel?: string
  inputId: string
  inputLabel: string
  url: string
}) {
  return (
    <Box className="d-flex mb-2" sx={{height: '32px'}}>
      <label htmlFor={inputId} className="sr-only">
        {inputLabel}
      </label>
      <input
        id={inputId}
        type="text"
        className="form-control input-monospace input-sm color-bg-subtle"
        data-autoselect
        value={url}
        readOnly
        style={{flexGrow: 1}}
      />
      <CopyToClipboardButton
        className="ml-1 mr-0"
        sx={{width: '32px'}}
        textToCopy={url}
        ariaLabel={buttonAriaLabel}
        tooltipProps={{direction: 'nw'}}
      />
    </Box>
  )
}

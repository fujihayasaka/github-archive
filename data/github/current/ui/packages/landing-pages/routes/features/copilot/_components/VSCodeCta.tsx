import {InlineLink, Text} from '@primer/react-brand'
import {analyticsEvent} from '../../../../lib/analytics'
import VSCodeIcon from '../_assets/ide-icons/vscode.svg'

interface VSCodeCtaProps {
  smaller?: boolean
  location?: string
}

export default function VSCodeCta({smaller, location}: VSCodeCtaProps) {
  return (
    <Text size={smaller ? '100' : undefined} className={`vscode-cta${smaller ? ' vscode-cta--small' : ''}`}>
      Already have{' '}
      <span className="no-wrap">
        <img src={VSCodeIcon} alt="" width="24" height="24" aria-hidden="true" /> {smaller ? 'VS' : 'Visual Studio'}{' '}
        Code?
      </span>{' '}
      <InlineLink
        href="vscode://github.copilot-chat"
        {...analyticsEvent({
          action: 'open_vscode',
          tag: 'a',
          context: 'click to try copilot in vscode',
          location: location || 'hero',
        })}
        aria-label="Open Visual Studio Code now"
      >
        Open&nbsp;now
      </InlineLink>
    </Text>
  )
}

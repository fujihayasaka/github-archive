import {Button, Image, Text} from '@primer/react-brand'
import {analyticsEvent} from '../../../../lib/analytics'

interface IdeItemProps {
  href: string
  action: string
  location: string
  image: string
  text: string
  appendix?: string
}

export default function IdeItem({href, action, location, image, text, appendix}: IdeItemProps) {
  return (
    <li className="lp-IDE-item" data-ide={action}>
      <Button
        as="a"
        href={href}
        hasArrow={false}
        className="lp-Features-editorButton"
        {...analyticsEvent({
          action,
          tag: 'icon',
          context: 'editors',
          location,
        })}
      >
        <Image src={`${image}?v=1`} alt="" width="70" height="70" />
        <Text as="div" size="100" weight="normal" className="lp-IDE-item-text">
          {text} <span className="lp-IDE-item-text-appendix">{appendix}</span>
        </Text>
      </Button>
      <Text as="div" size="100" weight="normal" className="lp-IDE-item-subtext" aria-hidden="true">
        {text} {appendix}
      </Text>
    </li>
  )
}

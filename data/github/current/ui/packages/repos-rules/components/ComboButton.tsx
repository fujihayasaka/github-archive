import type {FC} from 'react'
import {useRef, useState} from 'react'
import type {ButtonProps} from '@primer/react'
import {Button, ButtonGroup, IconButton, ActionMenu, ActionList, Label, Box} from '@primer/react'
import {Tooltip} from '@primer/react/next'
import {TriangleDownIcon} from '@primer/octicons-react'
import {Link} from '@github-ui/react-core/link'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {isFeatureEnabled} from '@github-ui/feature-flags'

export type ComboButtonAction =
  | {
      text: string
      onClick: () => void
      href?: never
      reloadDocument?: never
    }
  | {
      text: string
      onClick?: () => void
      href: string
      reloadDocument?: boolean
    }

type ComboButtonProps = {
  actions?: ComboButtonAction[]
  ariaLabel: string
}

const ButtonOrLinkButton: FC<ComboButtonAction & Pick<ButtonProps, 'variant'>> = ({text, href, ...props}) => {
  if (href) {
    return (
      <Button type="button" as={Link} to={href} {...props}>
        {text}
      </Button>
    )
  }

  return (
    <Button type="button" {...props}>
      {text}
    </Button>
  )
}

export const ComboButton: FC<ComboButtonProps> = ({actions, ariaLabel}) => {
  const buttonGroupRef = useRef<HTMLDivElement>(null)
  const [isButtonGroupMenuOpen, setButtonGroupMenuOpen] = useState(false)
  const enabled = isFeatureEnabled('lifecycle_label_name_updates')

  if (actions?.length === 1) {
    return <ButtonOrLinkButton {...actions[0]!} />
  }

  if ((actions?.length || 0) > 1) {
    return (
      <>
        <ButtonGroup ref={buttonGroupRef} className="my-2">
          <ButtonOrLinkButton {...actions![0]!} variant="primary" />
          <Tooltip
            text={ariaLabel}
            direction="sw"
            sx={{
              borderTopLeftRadius: 'var(--borderRadius-medium) !important',
              borderBottomLeftRadius: 'var(--borderRadius-medium) !important',
            }}
          >
            {/* // wrapping in tooltip breaks button group styles, manually override borders for now */}
            <IconButton
              aria-expanded={isButtonGroupMenuOpen}
              variant="primary"
              icon={TriangleDownIcon}
              onClick={() => setButtonGroupMenuOpen(prev => !prev)}
              aria-label={ariaLabel}
              sx={{
                borderTopRightRadius: 'var(--borderRadius-medium) !important',
                borderBottomRightRadius: 'var(--borderRadius-medium) !important',
                borderTopLeftRadius: '0px !important',
                borderBottomLeftRadius: '0px !important',
              }}
            />
          </Tooltip>
        </ButtonGroup>

        <ActionMenu anchorRef={buttonGroupRef} open={isButtonGroupMenuOpen} onOpenChange={setButtonGroupMenuOpen}>
          <ActionMenu.Overlay>
            <ActionList>
              {actions!.slice(1).map(action => {
                if (action.href) {
                  return (
                    <ActionList.LinkItem {...action} as={Link} key={action.text} to={action.href}>
                      <Box sx={{whiteSpace: 'nowrap', overflow: 'hidden'}}>{action.text}</Box>
                      {action.text === 'New push ruleset' && (
                        <ActionList.TrailingVisual>
                          {enabled ? <BetaLabel /> : <Label variant="success">Beta</Label>}
                        </ActionList.TrailingVisual>
                      )}
                    </ActionList.LinkItem>
                  )
                }

                return (
                  <ActionList.Item key={action.text} onSelect={action.onClick}>
                    {action.text}
                  </ActionList.Item>
                )
              })}
            </ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>
      </>
    )
  }

  return null
}

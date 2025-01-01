import {ShieldIcon} from '@primer/octicons-react'
import {LABELS} from './constants/labels'
import {noop} from '@github-ui/noop'
import {IssueTemplateItem} from './IssueTemplateItem'

type SecurityPolicyItemProps = {
  link: string | null | undefined
}

export const SecurityPolicyRow = ({link}: SecurityPolicyItemProps): JSX.Element => {
  return (
    <IssueTemplateItem
      filename="default-security-policy"
      link={link}
      externalLink
      onTemplateSelected={noop}
      name={LABELS.securityPolicyName}
      about={LABELS.securityPolicyDescription}
      trailingIcon={<ShieldIcon />}
    />
  )
}

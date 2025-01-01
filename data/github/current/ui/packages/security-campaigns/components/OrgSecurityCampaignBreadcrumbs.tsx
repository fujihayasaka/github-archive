import {Breadcrumbs} from '@primer/react'

export interface OrgSecurityCampaignBreadcrumbsProps {
  href: string
  text: string
  selectedText: string
}

export function OrgSecurityCampaignBreadcrumbs({href, text, selectedText}: OrgSecurityCampaignBreadcrumbsProps) {
  return (
    <Breadcrumbs className="mb-2">
      <Breadcrumbs.Item href={href}>{text}</Breadcrumbs.Item>
      <Breadcrumbs.Item selected>{selectedText}</Breadcrumbs.Item>
    </Breadcrumbs>
  )
}

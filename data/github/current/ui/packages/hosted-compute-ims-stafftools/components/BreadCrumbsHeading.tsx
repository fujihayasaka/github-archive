import {Box, Breadcrumbs} from '@primer/react'
import {Spacing, breadcrumbLink} from '../helpers/style'
import {useNavigate} from '@github-ui/use-navigate'

interface BreadCrumbsHeadingProps {
  previousPageLink: string
  previousPageTitle: string
  currentPageTitle: string
}

export function BreadcrumbsHeading(props: BreadCrumbsHeadingProps) {
  const navigate = useNavigate()

  return (
    <Box sx={{mb: Spacing.StandardPadding}}>
      <Breadcrumbs>
        <Breadcrumbs.Item sx={breadcrumbLink} onClick={() => navigate(props.previousPageLink)}>
          {props.previousPageTitle}
        </Breadcrumbs.Item>
        <Breadcrumbs.Item selected>{props.currentPageTitle}</Breadcrumbs.Item>
      </Breadcrumbs>
    </Box>
  )
}

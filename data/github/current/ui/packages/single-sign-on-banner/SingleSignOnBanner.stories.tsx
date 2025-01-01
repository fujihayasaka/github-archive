import type {Meta} from '@storybook/react'
import {SingleSignOnBanner} from './SingleSignOnBanner'
import {Wrapper} from '@github-ui/react-core/test-utils'

const meta = {
  title: 'Recipes/SingleSignOnBanner',
  component: SingleSignOnBanner,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof SingleSignOnBanner>

export default meta

export const SingleSignOnBannerExample = () => {
  return (
    <Wrapper>
      <SingleSignOnBanner protectedOrgs={['github', 'acme', 'microsoft']} />
    </Wrapper>
  )
}

export const SingleSignOnBannerMaxVisibleOrgsExample = () => {
  return (
    <Wrapper>
      <SingleSignOnBanner
        protectedOrgs={['github', 'acme', 'microsoft', 'contoso', 'copilot', 'primer']}
        maxVisibleOrgNames={3}
      />
    </Wrapper>
  )
}

export const SingleSignOnBannerNoVisibleOrgsExample = () => {
  return (
    <Wrapper>
      <SingleSignOnBanner
        protectedOrgs={['github', 'acme', 'microsoft', 'contoso', 'copilot', 'primer']}
        maxVisibleOrgNames={0}
      />
    </Wrapper>
  )
}

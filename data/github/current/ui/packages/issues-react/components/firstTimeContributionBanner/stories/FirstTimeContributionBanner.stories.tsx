import type {Meta, StoryObj} from '@storybook/react'
import {
  FirstTimeContributionBannerDisplay,
  type FirstTimeContributionBannerDisplayProps,
} from '../FirstTimeContributionBannerDisplay'

const meta = {
  title: 'FirstTimeContributionBanner',
  component: FirstTimeContributionBannerDisplay,
} satisfies Meta<typeof FirstTimeContributionBannerDisplay>

const dismissForThisRepo = () => {
  alert('Banner dismissed for this repo')
}

const dismissForAllRepos = () => {
  alert('Banner dismissed for all repos')
}

const defaultArgs = {
  hasGoodFirstIssueIssues: false,
  repoNameWithOwner: 'pytorch/pytorch',
  contributeUrl: 'https://github.com/pytorch/pytorch/contribute',
  dismissForThisRepo,
  dismissForAllRepos,
} satisfies FirstTimeContributionBannerDisplayProps

export default meta

type Story = StoryObj<FirstTimeContributionBannerDisplayProps>

export const WithoutContributionGuidelines: Story = {
  name: 'Without contribution guidelines (links to open source guide)',
  args: {
    ...defaultArgs,
  },
  render: FirstTimeContributionBannerDisplay,
}

export const WithContributionGuidelines: Story = {
  args: {
    ...defaultArgs,
    contributingGuidelinesUrl: 'https://github.com/pytorch/pytorch/blob/main/CONTRIBUTING.md',
  },
  render: FirstTimeContributionBannerDisplay,
}

export const WithGoodFirstIssues: Story = {
  args: {
    ...defaultArgs,
    hasGoodFirstIssueIssues: true,
  },
  render: FirstTimeContributionBannerDisplay,
}

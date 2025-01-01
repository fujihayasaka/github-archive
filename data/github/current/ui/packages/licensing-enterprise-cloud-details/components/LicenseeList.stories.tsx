import {LicenseeList} from './LicenseeList'
import type {Meta, StoryObj} from '@storybook/react'

const meta: Meta<typeof LicenseeList> = {
  title: 'Apps/Licensing/Enterprise Cloud/LicenseeList',
  component: LicenseeList,
}
export default meta

type Story = StoryObj<typeof LicenseeList>

export const Empty: Story = {
  args: {
    licensees: [],
    isFetching: false,
  },
  name: 'Empty list',
}

export const Loading: Story = {
  args: {
    licensees: [],
    isFetching: true,
  },
  name: 'Loading',
}

export const Error: Story = {
  args: {
    licensees: [],
    isError: true,
    isFetching: false,
    currentPage: 1,
    totalPages: 1,
  },
  name: 'Error',
}

export const WithLicensees: Story = {
  args: {
    licensees: [
      {
        id: '1',
        accessType: 'Member',
        avatarUrl: 'https://avatars.githubusercontent.com/u/583231',
        login: 'octocat',
        license: 'Enterprise',
        fullName: 'The Octocat',
      },
      {
        id: '2',
        accessType: 'Admin',
        avatarUrl: 'https://avatars.githubusercontent.com/u/583231',
        login: 'hubot',
        license: 'Visual Studio',
        fullName: 'Hubot',
      },
    ],
    isFetching: false,
    currentPage: 1,
    totalPages: 1,
  },
  name: 'With licensees',
}

export const WithPagination: Story = {
  args: {
    licensees: [
      {
        id: '1',
        accessType: 'Member',
        avatarUrl: 'https://avatars.githubusercontent.com/u/583231',
        login: 'octocat',
        license: 'Enterprise',
        fullName: 'The Octocat',
      },
      {
        id: '2',
        accessType: 'Admin',
        avatarUrl: 'https://avatars.githubusercontent.com/u/583231',
        login: 'hubot',
        license: 'Enterprise',
        fullName: 'Hubot',
      },
      {
        id: '3',
        accessType: 'Member',
        avatarUrl: 'https://avatars.githubusercontent.com/u/583231',
        login: 'monalisa',
        license: 'Visual Studio',
        fullName: 'Mona Lisa',
      },
    ],
    isFetching: false,
    currentPage: 1,
    totalPages: 3,
  },
  name: 'With pagination',
}

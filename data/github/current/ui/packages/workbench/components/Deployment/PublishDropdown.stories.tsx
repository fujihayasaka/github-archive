import type {Meta} from '@storybook/react'

import {
  publishingContextDecoratorArgs,
  publishingContextDecoratorArgTypes,
  withPublishingContext,
} from '../../contexts/.storybook/WithPublishingContext'
import {
  withWorkbenchContext,
  workbenchContextDecoratorArgs,
  workbenchContextDecoratorArgTypes,
} from '../../contexts/.storybook/WithWorkbenchContext'
import {PublishDropdown} from './PublishDropdown'

export default {
  title: 'Apps/Workbench/Components/Deployment/PublishDropdown',
  component: PublishDropdown,
  argTypes: {
    variant: {},
    ...workbenchContextDecoratorArgTypes,
    ...publishingContextDecoratorArgTypes,
  },
  args: {
    variant: 'button',
    ...workbenchContextDecoratorArgs,
    ...publishingContextDecoratorArgs,
  },
  decorators: [withPublishingContext, withWorkbenchContext],
} satisfies Meta<typeof PublishDropdown>

export const Unpublished = {
  args: {
    publishingStatus: 'unpublished',
  },
}

export const PublishingFirstTime = {
  args: {
    publishingStatus: 'publishingFirstTime',
  },
}

export const PublishedFirstTime = {
  args: {
    publishingStatus: 'publishedFirstTime',
  },
}

export const Published = {
  args: {
    publishingStatus: 'published',
  },
}

export const PublishedOutOfDate = {
  args: {
    publishingStatus: 'published',
    isPublishUpToDate: false,
  },
}

export const Republishing = {
  args: {
    publishingStatus: 'republishing',
  },
}

export const RepublishFailed = {
  args: {
    publishingStatus: 'republishFailed',
  },
}

export const NotPublishableAndPublished = {
  args: {
    publishingStatus: 'published',
    canCurrentlyPublish: false,
  },
}

export const NotPublishableAndUnpublished = {
  args: {
    publishingStatus: 'unpublished',
    canCurrentlyPublish: false,
  },
}

export const PublishedMissingUrl = {
  args: {
    publishingStatus: 'published',
    publishedUrl: undefined,
  },
}

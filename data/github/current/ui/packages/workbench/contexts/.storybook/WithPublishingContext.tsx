import {action} from '@storybook/addon-actions'
import type {Decorator} from '@storybook/react'

import {DeploymentVisibility} from '../../types/deployment-types'
import {PublishingContext, type PublishingContextData} from '../PublishingContext'

export const publishingContextDecoratorArgTypes = {
  canCurrentlyPublish: {
    control: 'boolean',
    description: 'Can a new publish process be started?',
  },
  publishedUrl: {
    control: 'text',
    description: 'The URL of the published deployment',
  },
  publishingStatus: {
    control: 'select',
    options: [
      'unpublished',
      'publishingFirstTime',
      'publishedFirstTime',
      'published',
      'republishing',
      'republishFailed',
    ],
    description: 'The status of the deployment',
  },
  isPublishUpToDate: {
    control: 'boolean',
    description: 'Is the published spark on the same SHA as our most recent iteration?',
  },
  previewUrl: {
    control: 'text',
    description: 'The URL for the read-only preview',
  },
  publishingVisibility: {
    control: 'select',
    options: Object.values(DeploymentVisibility),
    description: 'The visibility of the published deployment',
  },
}

export const publishingContextDecoratorArgs = {
  canCurrentlyPublish: true,
  publishedUrl: 'https://12345678901234567890-12345678901234567890.github.app',
  publishingStatus: 'unpublished',
  isPublishUpToDate: true,
  previewUrl: 'https://preview-12345678901234567890.github.app',
  publishingVisibility: DeploymentVisibility.OnlyOwner,
}

export const withPublishingContext: Decorator = (Story, {args}) => {
  const contextValue = {
    publishingStatus: args.publishingStatus,
    publishedUrl: args.publishedUrl,
    isPublishUpToDate: args.isPublishUpToDate,
    previewUrl: args.previewUrl,
    canCurrentlyPublish: args.canCurrentlyPublish,
    startDeploymentPipeline: action('startDeploymentPipeline'),
    visibility: args.publishingVisibility,
    setVisibility: action('setVisibility'),
    unpublish: action('unpublish'),
    cancelPublishing: action('cancelPublishing'),
  } as PublishingContextData

  return (
    <PublishingContext.Provider value={contextValue}>
      <Story />
    </PublishingContext.Provider>
  )
}

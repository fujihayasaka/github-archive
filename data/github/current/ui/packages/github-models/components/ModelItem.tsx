import commonStyles from '@github-ui/marketplace-common/marketplace-common.module.css'
import {testIdProps} from '@github-ui/test-id-props'
import styles from './ModelItem.module.css'

import {Heading, Label} from '@primer/react'
import type {FeaturedModel} from '@github-ui/marketplace-common'
import {modelPath} from '@github-ui/paths'
import {ModelsAvatar} from './ModelsAvatar'

import {normalizeModelPublisher} from '../utils/normalize-model-strings'

export interface ModelItemProps {
  model: Omit<FeaturedModel, 'id'>
  isFeatured?: boolean
  href?: string
}

export default function ModelItem({model, isFeatured, href}: ModelItemProps) {
  const modelUrl = href || modelPath(model)
  // Jamba logo has some padding so we need to adjust the size
  const isJamba = model.publisher === 'AI21 Labs'
  const jambaDivClass = isJamba ? commonStyles['marketplace-logo--jamba-div'] : ''
  const jambaLogoClass = isJamba ? commonStyles['marketplace-logo--jamba-logo'] : ''

  return (
    <div
      className={`position-relative border rounded-2 d-flex ${commonStyles['marketplace-item']} ${
        isFeatured ? 'flex-column flex-items-center p-4' : 'gap-3 p-3'
      }`}
      {...testIdProps('marketplace-item')}
    >
      <div
        className={`flex-shrink-0 rounded-3 overflow-hidden ${commonStyles['marketplace-logo']} ${jambaDivClass}`}
        {...testIdProps('logo')}
      >
        <ModelsAvatar
          model={model}
          size={36}
          className={`${commonStyles['marketplace-model-avatar-icon']} ${jambaLogoClass} box-shadow-none color-fg-default`}
          data-testid="logo-image"
        />
      </div>
      {isFeatured ? (
        <div
          className="d-flex flex-column flex-items-center height-full width-full text-center"
          {...testIdProps('featured-item')}
        >
          <Heading as="h3" className="mt-3 d-flex f4 lh-condensed">
            <a href={modelUrl} className={`fgColor-default line-clamp-1 ${commonStyles['marketplace-item-link']}`}>
              {model.friendly_name}
            </a>
          </Heading>
          <p className="mt-2 mb-auto text-small fgColor-muted line-clamp-2">
            by {normalizeModelPublisher(model.publisher)}
          </p>
          {model.summary && <p className="mt-2 text-small fgColor-muted line-clamp-2">{model.summary}</p>}
          <Label
            variant="secondary"
            size="large"
            className={styles.modelItemLabel}
            {...testIdProps('listing-type-label')}
          >
            Model
          </Label>
        </div>
      ) : (
        <div className="flex-1" {...testIdProps('non-featured-item')}>
          <div className="d-flex flex-justify-between flex-items-start gap-3">
            <h3 className="d-flex f4 lh-condensed">
              <a href={modelUrl} className={`${commonStyles['marketplace-item-link']} line-clamp-1`}>
                {model.friendly_name}
              </a>
            </h3>
            <Label variant="secondary">Model</Label>
          </div>
          {model.summary && <p className="mt-1 mb-0 text-small fgColor-muted line-clamp-2">{model.summary}</p>}
          {!model.summary && (
            <p className="mt-1 mb-0 text-small fgColor-muted line-clamp-2">
              {normalizeModelPublisher(model.publisher)}
            </p>
          )}
        </div>
      )}
    </div>
  )
}

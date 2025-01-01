import {CheckIcon, MarkGithubIcon} from '@primer/octicons-react'
import {modelsCatalogPath, modelPlaygroundPath} from '@github-ui/paths'
import type {GettingStartedPayload} from '../../../types'
import ModelItem from '../../../components/ModelItem'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import styles from './Playground.module.css'
import {testIdProps} from '@github-ui/test-id-props'

export const NoModel = () => {
  const {featuredModels = []} = useRoutePayload<GettingStartedPayload>()

  return (
    <div className="flex-1 d-flex flex-column flex-justify-center flex-items-center p-3">
      <MarkGithubIcon size={64} className="pb-3" />
      <p className="h4">Welcome to GitHub Models</p>
      <p className="color-fg-muted">
        A catalog and playground of AI models to help you build AI features and products.
      </p>
      <p>
        <span className="fgColor-success pr-1">
          <CheckIcon size={16} />
        </span>
        <span className="text-bold">Model switching:</span> A single API key for all models &amp; billing.
      </p>
      <p>
        <span className="fgColor-success pr-1">
          <CheckIcon size={16} />
        </span>
        <span className="text-bold">Quick personal setup:</span> GitHub PAT to install models in your projects.
      </p>
      <p>
        <span className="fgColor-success pr-1">
          <CheckIcon size={16} />
        </span>
        <span className="text-bold">Free to start:</span> No charges until you hit our rate limits.
      </p>
      <p className="pt-md-10">
        Select a model to get started, or{' '}
        <a className="Link--inTextBlock" href={modelsCatalogPath()}>
          explore the full model catalog
        </a>
        .
      </p>
      <div
        className={`pt-3 d-flex flex-column flex-md-row gap-3 ${styles.featuredGrid}`}
        {...testIdProps('featured-model-container')}
        data-hpc
      >
        {featuredModels.map(model => (
          <ModelItem key={model.id} model={model} href={modelPlaygroundPath(model)} />
        ))}
      </div>
    </div>
  )
}

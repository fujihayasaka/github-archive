import type {Model} from '@github-ui/marketplace-common'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {testIdProps} from '@github-ui/test-id-props'
import type {ShowModelPayload} from '../../../types'
import styles from './Readme.module.css'

import {SafeHTMLBox} from '@github-ui/safe-html'
import {PUBLISHER} from '../../../utils/normalize-model-strings'

export function Readme() {
  const {model, modelReadme} = useRoutePayload<ShowModelPayload>()

  return (
    <>
      <MarkdownPublisherHeroImage model={model} />
      <SafeHTMLBox data-hpc html={modelReadme} className="p-3" {...testIdProps('readme-content')} />
    </>
  )
}

const MarkdownHero = ({src, webp, alt}: {src: string; webp: string; alt: string}) => {
  return (
    <div className={styles.markdownHeroContainer} {...testIdProps('readme-hero')}>
      <picture>
        <source srcSet={webp} type="image/webp" />
        <img className={styles.markdownHeroLogo} src={src} alt={alt} />
      </picture>
    </div>
  )
}

function MarkdownPublisherHeroImage({model}: {model: Model}) {
  const lowercaseKey = model.publisher.toLowerCase()

  switch (lowercaseKey) {
    case PUBLISHER.Cohere:
      return (
        <MarkdownHero
          src="/images/modules/marketplace/models/families/cohere-hero.jpg"
          webp="/images/modules/marketplace/models/families/cohere-hero.webp"
          alt={model.publisher}
        />
      )
    case PUBLISHER.Core42:
      return (
        <MarkdownHero
          src="/images/modules/marketplace/models/families/core42-hero.jpg"
          webp="/images/modules/marketplace/models/families/core42-hero.webp"
          alt={model.publisher}
        />
      )
    case PUBLISHER.DeepSeek:
      return (
        <MarkdownHero
          src="/images/modules/marketplace/models/families/deepseek-hero.jpg"
          webp="/images/modules/marketplace/models/families/deepseek-hero.webp"
          alt={model.publisher}
        />
      )
    case PUBLISHER.Meta:
      return (
        <MarkdownHero
          src="/images/modules/marketplace/models/families/meta-hero.jpg"
          webp="/images/modules/marketplace/models/families/meta-hero.webp"
          alt={model.publisher}
        />
      )
    case PUBLISHER.Microsoft:
      return (
        <MarkdownHero
          src="/images/modules/marketplace/models/families/microsoft-hero.jpg"
          webp="/images/modules/marketplace/models/families/microsoft-hero.webp"
          alt={model.publisher}
        />
      )
    case PUBLISHER.Mistral:
    case PUBLISHER.MistralAI:
    case PUBLISHER.MistralAI2:
      return (
        <MarkdownHero
          src="/images/modules/marketplace/models/families/mistral-hero.jpg"
          webp="/images/modules/marketplace/models/families/mistral-hero.webp"
          alt={model.publisher}
        />
      )
    case PUBLISHER.AI21Labs:
      return (
        <MarkdownHero
          src="/images/modules/marketplace/models/families/ai21labs-hero.jpg"
          webp="/images/modules/marketplace/models/families/ai21labs-hero.webp"
          alt={model.publisher}
        />
      )
    case PUBLISHER.OpenAI:
    case PUBLISHER.OpenAIEVault:
      return (
        <MarkdownHero
          src="/images/modules/marketplace/models/families/openai-hero.jpg"
          webp="/images/modules/marketplace/models/families/openai-hero.webp"
          alt={model.publisher}
        />
      )
    case PUBLISHER.xAI:
      return (
        <MarkdownHero
          src="/images/modules/marketplace/models/families/xai-hero.jpg"
          webp="/images/modules/marketplace/models/families/xai-hero.webp"
          alt={model.publisher}
        />
      )
    default:
      return null
  }
}

import styles from './marketplace-header.module.css'
import useColorModes from '@github-ui/react-core/use-color-modes'
import {useMemo} from 'react'
import MarketplaceSearchField from './MarketplaceSearchField'
import LegacyMarketplaceSearchField from './legacy/MarketplaceSearchField'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

export default function MarketplaceHeader() {
  const headerForegroundImages = ['models', 'sparklesmall', 'sparklelarge']
  const headerBackgroundImages = ['arrow', 'donut', 'semicircles', 'workflow']

  const colorMode = useColorModes()

  const newSearchFeatureFlag = useFeatureFlag('marketplace_search_improvements')

  const colorModeAwareAssetDirectory = useMemo(() => {
    switch (colorMode.colorMode) {
      case 'night':
        return 'dark'
      case 'day':
      default:
        return 'light'
    }
  }, [colorMode])
  return (
    <header
      className={`mb-2 border-bottom borderColor-default d-flex flex-items-start py-5 py-lg-4 position-relative ${styles['header']}`}
    >
      <div className="position-absolute top-0 left-0 right-0 bottom-0 overflow-hidden">
        <div className={`${styles['gradient']} ${styles['gradient-left']}`} />
        <div className={`${styles['gradient']} ${styles['gradient-right']}`} />
        <div className={`${styles['image-container-mobile']} md-container-xl position-relative height-full`}>
          {headerBackgroundImages.map(image => (
            <img
              key={image}
              src={`/images/modules/marketplace/header/${colorModeAwareAssetDirectory}/${image}.png`}
              srcSet={`/images/modules/marketplace/header/${colorModeAwareAssetDirectory}/${image}@2x.png 2x`}
              className={`position-absolute ${styles[image as keyof typeof styles]}`}
              alt=""
            />
          ))}
        </div>
      </div>
      <div className="container-xl m-auto width-full d-flex flex-items-center flex-column flex-lg-row-reverse flex-justify-between gap-4 px-3 pl-lg-4 pr-lg-5 pl-xl-3">
        <div className={`position-relative mb-4 mb-lg-0 user-select-none ${styles['image-wrapper']}`}>
          {headerForegroundImages.map(image => (
            <img
              key={image}
              src={`/images/modules/marketplace/header/${colorModeAwareAssetDirectory}/${image}.png`}
              srcSet={`/images/modules/marketplace/header/${colorModeAwareAssetDirectory}/${image}@2x.png 2x`}
              className={`position-absolute ${styles[image as keyof typeof styles]}`}
              alt=""
            />
          ))}
          <img
            src={`/images/modules/marketplace/header/${colorModeAwareAssetDirectory}/copilot.png`}
            srcSet={`/images/modules/marketplace/header/${colorModeAwareAssetDirectory}/copilot@2x.png 2x`}
            className={`m-lg-4 ${styles['copilot']}`}
            alt=""
          />
        </div>
        <div className={`text-center text-lg-left ${styles['header-content']}`}>
          <h1 className="lh-condensed text-wrap-balance">Enhance your workflow with extensions</h1>
          <p className="fgColor-muted f3">
            Tools from the community and partners to simplify tasks and automate processes
          </p>
          {newSearchFeatureFlag ? <MarketplaceSearchField /> : <LegacyMarketplaceSearchField />}
        </div>
      </div>
    </header>
  )
}

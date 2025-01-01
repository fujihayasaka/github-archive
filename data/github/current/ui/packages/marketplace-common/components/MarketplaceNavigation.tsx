import {useMemo, useState} from 'react'

import styles from './marketplace-navigation.module.css'

import {Button, NavList} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {
  AiModelIcon,
  AppsIcon,
  ArrowUpRightIcon,
  CommandPaletteIcon,
  CopilotIcon,
  FlameIcon,
  ListUnorderedIcon,
  PlayIcon,
  PlusIcon,
} from '@primer/octicons-react'
import type {Category} from '../types'
import {useCopilotApp} from '../contexts/CopilotAppContext'
import {useCategory} from '../contexts/CategoryContext'
import {useSearchType} from '../contexts/SearchTypeContext'

export type Props = {
  categories: {
    apps: Category[]
    actions: Category[]
  }
}

function Menu({categories}: Props) {
  const {copilotApp} = useCopilotApp()
  const {type} = useSearchType()
  const {category} = useCategory()

  const currentNavItem = useMemo(() => {
    if (!type && !category && !copilotApp) {
      return 'featured'
    } else if (type === 'apps' && copilotApp === 'true') {
      return 'copilot'
    } else if (category) {
      return category || ''
    }
    return ''
  }, [category, copilotApp, type])

  const currentType = useMemo(() => {
    if (type && !copilotApp) {
      if (type === 'apps') {
        return 'apps'
      } else if (type === 'actions') {
        return 'actions'
      } else if (type === 'models') {
        return 'models'
      }
    }
    return ''
  }, [copilotApp, type])

  return (
    <NavList>
      <NavList.Item href="/marketplace" {...(currentNavItem === 'featured' ? {'aria-current': 'page'} : {})}>
        <NavList.LeadingVisual>
          <FlameIcon />
        </NavList.LeadingVisual>
        Featured
      </NavList.Item>
      <NavList.Item
        href="/marketplace?type=apps&copilot_app=true"
        {...(currentNavItem === 'copilot' ? {'aria-current': 'page'} : {})}
      >
        <NavList.LeadingVisual>
          <CopilotIcon />
        </NavList.LeadingVisual>
        Copilot
      </NavList.Item>
      <NavList.Item defaultOpen={currentType === 'models'}>
        <NavList.LeadingVisual>
          <AiModelIcon />
        </NavList.LeadingVisual>
        Models
        <NavList.SubNav>
          <NavList.Item href="/marketplace?type=models" aria-current={currentType === 'models' ? 'page' : undefined}>
            <NavList.LeadingVisual>
              <ListUnorderedIcon />
            </NavList.LeadingVisual>
            Catalog
          </NavList.Item>
          <NavList.Item href="/marketplace/models">
            <NavList.LeadingVisual>
              <CommandPaletteIcon />
            </NavList.LeadingVisual>
            Playground
            <NavList.TrailingVisual>
              <ArrowUpRightIcon />
            </NavList.TrailingVisual>
          </NavList.Item>
        </NavList.SubNav>
      </NavList.Item>
      <NavList.Item defaultOpen={currentType === 'apps'}>
        <NavList.LeadingVisual>
          <AppsIcon />
        </NavList.LeadingVisual>
        Apps
        <NavList.SubNav>
          <NavList.Item
            href={`/marketplace?type=apps`}
            {...(currentType === 'apps' && currentNavItem === '' ? {'aria-current': 'page'} : {})}
          >
            All apps
          </NavList.Item>
          {categories?.apps?.map(cat => (
            <NavList.Item
              key={`apps-category-${cat.slug}`}
              href={`/marketplace?type=apps&category=${cat.slug}`}
              {...(currentType === 'apps' && currentNavItem === cat.slug ? {'aria-current': 'page'} : {})}
            >
              {cat.name}
            </NavList.Item>
          ))}
        </NavList.SubNav>
      </NavList.Item>
      <NavList.Item defaultOpen={currentType === 'actions'}>
        <NavList.LeadingVisual>
          <PlayIcon />
        </NavList.LeadingVisual>
        Actions
        <NavList.SubNav>
          <NavList.Item
            href={`/marketplace?type=actions`}
            {...(currentType === 'actions' && currentNavItem === '' ? {'aria-current': 'page'} : {})}
          >
            All actions
          </NavList.Item>
          {categories?.actions?.map(cat => (
            <NavList.Item
              key={`actions-category-${cat.slug}`}
              href={`/marketplace?type=actions&category=${cat.slug}`}
              {...(currentType === 'actions' && currentNavItem === cat.slug ? {'aria-current': 'page'} : {})}
            >
              {cat.name}
            </NavList.Item>
          ))}
        </NavList.SubNav>
      </NavList.Item>
      <NavList.Divider />
      <NavList.Item href="/marketplace/new">
        <NavList.LeadingVisual>
          <PlusIcon />
        </NavList.LeadingVisual>
        Create a new extension
      </NavList.Item>
    </NavList>
  )
}

export default function MarketplaceNavigation({categories}: Props) {
  const [isMenuOpen, setIsMenuOpen] = useState(false)
  const onMenuClose = () => setIsMenuOpen(false)

  return (
    <>
      <div className="hide-sm hide-md overflow-hidden">
        <Menu categories={categories} />
      </div>

      <Button block className="hide-lg hide-xl" onClick={() => setIsMenuOpen(true)}>
        Menu
      </Button>
      {isMenuOpen && (
        <Dialog title="Menu" onClose={onMenuClose} position={{narrow: 'bottom'}}>
          <div className={styles['negative-margin']}>
            <Menu categories={categories} />
          </div>
        </Dialog>
      )}
    </>
  )
}

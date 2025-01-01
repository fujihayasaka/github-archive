import {useMemo} from 'react'
import {UnderlineNav, PageLayout, useResponsiveValue} from '@primer/react'
import {BookIcon, LawIcon, ChecklistIcon, LogIcon} from '@primer/octicons-react'
import type {GettingStarted, ModelInputSchema, ShowModelPayload} from '../../../types'
import type {Model} from '@github-ui/marketplace-common'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {ModelOverviewHeader} from './ModelOverviewHeader'
import {GiveFeedback} from '../../../components/GiveFeedback'
import {MiniPlayground} from './MiniPlayground'
import SidebarInfo from '../../../components/ModelDetailsSidebar/SidebarInfo'
import {LanguagesSection} from '../../../components/ModelDetailsSidebar/LanguagesSection'
import {TagsSection} from '../../../components/ModelDetailsSidebar/TagsSection'
import {Link} from 'react-router-dom'
import {userHasAccessToModel} from '../../../utils/model-access'

const tabs = {
  readme: {
    name: 'README',
    icon: BookIcon,
  },
  transparency: {
    name: 'Transparency',
    icon: LogIcon,
  },
  evaluation: {
    name: 'Evaluation',
    icon: ChecklistIcon,
  },
  license: {
    name: 'License',
    icon: LawIcon,
  },
}

export type ModelLayoutTab = keyof typeof tabs

const noEvaluationReport = 'This model does not provide an evaluation report.'
const noTransparencyNotes = 'The model does not have specific notes.'
const noAdditionalTransparencyNotes = 'This model does not provide any additional notes.'

export function ModelLayout({
  activeTab,
  children,
  model,
  modelInputSchema,
  gettingStarted,
}: React.PropsWithChildren<{
  activeTab: ModelLayoutTab
  model: Model
  modelInputSchema: ModelInputSchema
  gettingStarted: GettingStarted
}>) {
  const {modelLicense, restrictedModels} = useRoutePayload<ShowModelPayload>()
  const {tags, task, evaluation, notes, supported_languages} = model
  const labels = {tags, task}
  const languages = supported_languages.filter(language => language !== null)
  const isMobile = useResponsiveValue({narrow: true}, false) as boolean
  const showEvaluation = evaluation && noEvaluationReport !== evaluation
  const showTransparency = notes && ![noTransparencyNotes, noAdditionalTransparencyNotes].includes(notes)

  const canUseModel = useMemo(() => {
    if (task !== 'chat-completion') return false
    return userHasAccessToModel(model, restrictedModels)
  }, [task, model, restrictedModels])

  const getNavItem = (tab: ModelLayoutTab) => {
    const {name: tabName, icon} = tabs[tab]
    return (
      <UnderlineNav.Item
        icon={icon}
        as={Link}
        to={`?tab=${tab}`}
        aria-current={activeTab === tab ? 'page' : undefined}
        tabIndex={0}
      >
        {tabName}
      </UnderlineNav.Item>
    )
  }

  return (
    <div className="d-flex flex-column">
      {isMobile && <GiveFeedback mobile />}
      <PageLayout columnGap="normal" padding={isMobile ? 'none' : 'normal'}>
        <PageLayout.Header>
          <ModelOverviewHeader model={model} gettingStarted={gettingStarted} canUseModel={canUseModel} />
        </PageLayout.Header>
        <PageLayout.Content as="div" className={`p-0 ${isMobile && 'px-3 pb-3'}`}>
          {canUseModel && <MiniPlayground model={model} modelInputSchema={modelInputSchema} isMobile={isMobile} />}
          <div className="border rounded-2">
            <UnderlineNav aria-label="Model navigation">
              {getNavItem('readme')}
              {showEvaluation && getNavItem('evaluation')}
              {showTransparency && getNavItem('transparency')}
              {modelLicense && getNavItem('license')}
            </UnderlineNav>
            <div className="p-2">{children}</div>
          </div>
          {isMobile && (
            <div className="d-flex flex-column gap-3 pt-3 pb-5">
              {(labels.tags.length > 0 || labels.task) && <TagsSection labels={labels} />}
              {languages.length > 0 && <LanguagesSection languages={languages} />}
            </div>
          )}
        </PageLayout.Content>
        {!isMobile && (
          <PageLayout.Pane>
            <SidebarInfo model={model} />
          </PageLayout.Pane>
        )}
      </PageLayout>
    </div>
  )
}

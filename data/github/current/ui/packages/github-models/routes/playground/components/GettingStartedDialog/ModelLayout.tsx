import {useMemo} from 'react'
import {UnderlineNav, Box, PageLayout, useResponsiveValue} from '@primer/react'
import {BookIcon, LawIcon, ChecklistIcon, LogIcon} from '@primer/octicons-react'
import type {GettingStarted, ModelInputSchema, ShowModelPayload} from '../../../../types'
import type {Model} from '@github-ui/marketplace-common'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {OverviewHeader} from './OverviewHeader'
import {GiveFeedback} from './GiveFeedback'
import {MiniPlayground} from './MiniPlayground'
import SidebarInfo from '../SidebarInfo'
import {LanguagesSection} from '../LanguagesSection'
import {TagsSection} from '../TagsSection'

export type ModelLayoutTab = 'readme' | 'transparency' | 'evaluation' | 'license'

export function ModelLayout({
  activeTab,
  selectTab,
  children,
  model,
  modelInputSchema,
  gettingStarted,
}: React.PropsWithChildren<{
  activeTab: ModelLayoutTab
  selectTab:
    | ((tab: ModelLayoutTab, e: React.KeyboardEvent<HTMLAnchorElement> | React.MouseEvent<HTMLAnchorElement>) => void)
    | null
  model: Model
  modelInputSchema: ModelInputSchema
  gettingStarted: GettingStarted
}>) {
  const {modelLicense, canUseO1Models} = useRoutePayload<ShowModelPayload>()
  const {tags, task} = model
  const labels = {tags, task}
  const noEvaluationReport = 'This model does not provide an evaluation report.'
  const noTransparencyNotes = 'The model does not have specific notes.'
  const noAdditionalTransparencyNotes = 'This model does not provide any additional notes.'
  const languages = model.supported_languages.filter(language => language !== null)
  const isMobile = useResponsiveValue({narrow: true}, false)

  const canUseModel = useMemo(() => {
    if (model.task !== 'chat-completion') {
      return false
    }
    if (model.static_model) {
      return false
    }
    if (model.name === 'o1-mini' || model.name === 'o1-preview') {
      return canUseO1Models
    }

    return true
  }, [canUseO1Models, model])

  return (
    <div className="d-flex flex-column">
      <Box
        sx={{
          display: ['block', 'block', 'none'],
        }}
      >
        <GiveFeedback mobile />
      </Box>

      <PageLayout columnGap="normal" sx={{p: isMobile ? 0 : 3}}>
        <PageLayout.Header>
          <OverviewHeader model={model} gettingStarted={gettingStarted} />
        </PageLayout.Header>

        <PageLayout.Content as="div" sx={{p: isMobile ? 3 : 0, pt: 0}}>
          {canUseModel && (
            <div>
              <MiniPlayground model={model} modelInputSchema={modelInputSchema} />
            </div>
          )}
          <Box
            sx={{
              width: '100%',
              borderColor: 'border.default',
              borderStyle: 'solid',
              borderWidth: 1,
              borderRadius: 2,
              display: 'flex',
              flexDirection: 'column',
              boxShadow: 'var(--shadow-resting-small,var(--color-shadow-small))',
            }}
          >
            <div>
              <UnderlineNav aria-label="Model navigation">
                <UnderlineNav.Item
                  icon={BookIcon}
                  onSelect={e => selectTab && selectTab('readme', e)}
                  aria-current={activeTab === 'readme' ? 'page' : undefined}
                >
                  README
                </UnderlineNav.Item>
                {model.evaluation && noEvaluationReport !== model.evaluation && (
                  <UnderlineNav.Item
                    icon={ChecklistIcon}
                    onSelect={e => selectTab && selectTab('evaluation', e)}
                    aria-current={activeTab === 'evaluation' ? 'page' : undefined}
                  >
                    Evaluation
                  </UnderlineNav.Item>
                )}
                {model.notes &&
                  noTransparencyNotes !== model.notes &&
                  noAdditionalTransparencyNotes !== model.notes && (
                    <UnderlineNav.Item
                      icon={LogIcon}
                      onSelect={e => selectTab && selectTab('transparency', e)}
                      aria-current={activeTab === 'transparency' ? 'page' : undefined}
                    >
                      Transparency
                    </UnderlineNav.Item>
                  )}
                {modelLicense && (
                  <UnderlineNav.Item
                    icon={LawIcon}
                    onSelect={e => selectTab && selectTab('license', e)}
                    aria-current={activeTab === 'license' ? 'page' : undefined}
                  >
                    License
                  </UnderlineNav.Item>
                )}
              </UnderlineNav>
            </div>
            <Box sx={{p: [2, 2, 3]}}>{children}</Box>
          </Box>
          <Box sx={{display: ['flex', 'flex', 'none'], flexDirection: 'column', gap: 3, pt: 3, pb: 5}}>
            {(labels.tags.length > 0 || labels.task) && <TagsSection labels={labels} />}
            {languages.length > 0 && <LanguagesSection languages={languages} />}
          </Box>
        </PageLayout.Content>
        <PageLayout.Pane hidden={{narrow: true, regular: false}}>
          <SidebarInfo model={model} />
        </PageLayout.Pane>
      </PageLayout>
    </div>
  )
}

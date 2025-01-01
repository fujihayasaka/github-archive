import {DismissibleFlashOrToast, type FlashAlert} from '@github-ui/dismissible-flash'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {ListView} from '@github-ui/list-view'
import {ListItemActionBar} from '@github-ui/list-view/ListItemActionBar'
import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ListItem} from '@github-ui/list-view/ListItem'
import {Link} from '@github-ui/react-core/link'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {DownloadIcon, FileDiffIcon, ReplyIcon, KebabHorizontalIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Box, Pagination, Text, IconButton} from '@primer/react'
import {useEffect, useRef, useState} from 'react'
import {Blankslate} from '../components/Blankslate'
import {BorderBox} from '../components/BorderBox'
import {downloadRuleset} from '../helpers/export-ruleset'
import {useRelativeNavigation} from '../hooks/use-relative-navigation'
import type {HistorySummaryRoutePayload, Ruleset} from '../types/rules-types'
import {capitalize} from '../helpers/string'
import {useRuleStrings} from '../hooks/use-rule-strings'
import styles from './HistorySummaryPage.module.css'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

type NewListItemActionProps = {
  id: number
  staticAvatarUrl: string
  displayLogin: string
  createdAt: string
  readOnly?: boolean
  ruleset: Ruleset
  index: number
  isCurrent?: boolean
  setFlashAlert: (flashAlert: FlashAlert) => void
}

const NewListItem = ({
  id,
  staticAvatarUrl,
  displayLogin,
  createdAt,
  readOnly,
  ruleset,
  index,
  isCurrent,
  setFlashAlert,
}: NewListItemActionProps) => {
  const [menuOpen, setMenuOpen] = useState(false)

  return (
    <li className="Box-row pl-3 pr-3 py-2 d-flex flex-items-center flex-wrap">
      <GitHubAvatar sx={{alignSelf: 'center'}} src={staticAvatarUrl} />
      <span className="ml-3 mr-2">{displayLogin}</span>
      <div className="text-small color-fg-muted">
        <span>edited&nbsp;</span>
        <relative-time datetime={createdAt} />
      </div>
      <div className="ml-auto">
        <ActionMenu open={menuOpen} onOpenChange={() => setMenuOpen(!menuOpen)}>
          <ActionMenu.Anchor>
            <IconButton
              icon={KebabHorizontalIcon}
              size="small"
              variant="invisible"
              className="color-fg-muted align-center"
              aria-label={'History menu'}
            />
          </ActionMenu.Anchor>
          <ActionMenu.Overlay>
            <HistoryActionMenu
              rulesetName={ruleset.name}
              historyId={id}
              readOnly={readOnly}
              prevHistoryId={ruleset.histories?.[index + 1]?.id || null}
              canRestore={!isCurrent}
              setFlashAlert={setFlashAlert}
            />
          </ActionMenu.Overlay>
        </ActionMenu>
      </div>
    </li>
  )
}

/**
 * See ListView stories for a representation of this component.
 * ui/packages/list-view/src/stories/RepositoryRulesetHistory.stories.tsx
 * https://ui.githubapp.com/storybook/?path=/story/recipes-list-view-dotcom-pages--repository-ruleset-history
 */
export const HistorySummaryPage = () => {
  const {navigate, resolvePath} = useRelativeNavigation()
  const {readOnly, ruleset, hasMore, page} = useRoutePayload<HistorySummaryRoutePayload>()
  const [flashAlert, setFlashAlert] = useState<FlashAlert>({message: '', variant: 'default'})
  const flashRef = useRef<HTMLDivElement | null>(null)
  const {rulesetOrPolicy, rulesetsOrPolicies} = useRuleStrings()
  const rulesA11y = useFeatureFlag('rules_a11y')

  useEffect(() => {
    flashRef.current?.focus()
  }, [flashAlert, flashRef])

  const pageCount = hasMore ? page + 1 : page
  const showPagination = hasMore || page > 1

  return (
    <>
      <Box sx={{display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 3}}>
        <Box sx={{display: 'flex', gap: 1, alignItems: 'center', fontSize: 3}}>
          <Link to={resolvePath('../..')}>{capitalize(rulesetsOrPolicies)}</Link>
          <span>/</span>
          <Link to={resolvePath('..')}>
            <Text
              sx={{
                display: 'block',
                maxWidth: 200,
                textOverflow: 'ellipsis',
                overflowX: 'hidden',
                whiteSpace: 'nowrap',
              }}
            >
              {ruleset.name}
            </Text>
          </Link>
          <span>/</span>
          <span>History</span>
        </Box>
      </Box>
      <DismissibleFlashOrToast flashAlert={flashAlert} setFlashAlert={setFlashAlert} ref={flashRef} />
      <BorderBox>
        {(ruleset.histories?.length || 0) > 0 ? (
          rulesA11y ? (
            <ul className="d-flex flex-column">
              {ruleset.histories?.map(({id, created_at, updated_by, is_current}, index) => (
                <NewListItem
                  key={id}
                  id={id}
                  staticAvatarUrl={updated_by.static_avatar_url}
                  displayLogin={updated_by.display_login}
                  createdAt={created_at}
                  readOnly={readOnly}
                  ruleset={ruleset}
                  index={index}
                  isCurrent={is_current}
                  setFlashAlert={setFlashAlert}
                />
              ))}
            </ul>
          ) : (
            <ListView title={`${capitalize(rulesetOrPolicy)} history`} variant="compact">
              {ruleset.histories?.map(({id, created_at, updated_by, is_current}, index) => (
                <ListItem
                  key={id}
                  title={<ListItemTitle value={updated_by.display_login} containerClassName={styles.ListItemTitle_0} />}
                  secondaryActions={
                    <ListItemActionBar
                      staticMenuActions={[
                        {
                          key: 'history',
                          render: () => (
                            <HistoryActionMenu
                              rulesetName={ruleset.name}
                              historyId={id}
                              readOnly={readOnly}
                              prevHistoryId={ruleset.histories?.[index + 1]?.id || null}
                              canRestore={!is_current}
                              setFlashAlert={setFlashAlert}
                            />
                          ),
                        },
                      ]}
                    />
                  }
                >
                  <ListItemLeadingContent>
                    <GitHubAvatar sx={{marginRight: 2, alignSelf: 'center'}} src={updated_by.static_avatar_url} />
                  </ListItemLeadingContent>
                  <ListItemMainContent>
                    <ListItemDescription>
                      <span>edited&nbsp;</span>
                      <relative-time datetime={created_at} />
                    </ListItemDescription>
                  </ListItemMainContent>
                </ListItem>
              ))}
            </ListView>
          )
        ) : (
          <Blankslate heading={`No ${rulesetOrPolicy} history available`} />
        )}
      </BorderBox>
      {showPagination ? (
        <Pagination
          pageCount={pageCount}
          currentPage={page}
          onPageChange={(e, newPage) => {
            e.preventDefault()
            navigate('.', `page=${newPage}`, false)
          }}
          showPages={false}
        />
      ) : null}
    </>
  )
}

type HistoryActionMenuProps = {
  rulesetName: string
  historyId: number
  prevHistoryId: number | null
  readOnly?: boolean
  canRestore?: boolean
  setFlashAlert: (flashAlert: FlashAlert) => void
}

const HistoryActionMenu = ({
  rulesetName,
  historyId,
  prevHistoryId,
  readOnly = false,
  canRestore = true,
  setFlashAlert,
}: HistoryActionMenuProps) => {
  const {navigate, resolvePath} = useRelativeNavigation()
  const {rulesetOrPolicy} = useRuleStrings()

  return (
    <ActionList>
      <ActionList.Item
        onSelect={() =>
          prevHistoryId
            ? navigate(`./${historyId}/compare`, `compare_history_id=${prevHistoryId}`, false)
            : navigate(`./${historyId}/compare`, undefined, false)
        }
      >
        <ActionList.LeadingVisual>
          <FileDiffIcon size={16} />
        </ActionList.LeadingVisual>
        Compare changes
        <ActionList.Description variant="block">View a diff of these changes</ActionList.Description>
      </ActionList.Item>
      {!readOnly ? (
        <ActionList.Item
          disabled={!canRestore}
          onSelect={async () => {
            navigate('..', `history_id_to_restore=${historyId}`)
          }}
        >
          <ActionList.LeadingVisual>
            <ReplyIcon size={16} />
          </ActionList.LeadingVisual>
          Restore
          <ActionList.Description variant="block">Restore the {rulesetOrPolicy} to this version</ActionList.Description>
        </ActionList.Item>
      ) : null}
      <ActionList.LinkItem
        download={`${rulesetName}.json`}
        target="_self"
        onClick={async () => {
          try {
            await downloadRuleset(resolvePath(`../export_ruleset/${historyId}`), rulesetName)
          } catch {
            setFlashAlert({
              variant: 'danger',
              message: `Error exporting ${rulesetOrPolicy}`,
            })
          }
        }}
        className="text-decoration-skip"
      >
        <ActionList.LeadingVisual>
          <DownloadIcon size={16} />
        </ActionList.LeadingVisual>
        Download
        <ActionList.Description variant="block">Download raw file</ActionList.Description>
      </ActionList.LinkItem>
    </ActionList>
  )
}

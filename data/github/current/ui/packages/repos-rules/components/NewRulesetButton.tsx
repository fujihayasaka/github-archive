import {useState, type FC} from 'react'
import {type Ruleset, RulesetEnforcement} from '../types/rules-types'
import type {ComboButtonAction} from './ComboButton'
import {ComboButton} from './ComboButton'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useLocalStorage} from '@github-ui/use-safe-storage/local-storage'
import {ActionList, ActionMenu, Button, Box, Label, type BetterSystemStyleObject} from '@primer/react'
import {Link} from '@github-ui/react-core/link'
import {useJsonUpload} from '../hooks/use-json-upload'
import {useRelativeNavigation} from '../hooks/use-relative-navigation'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {TriangleDownIcon} from '@primer/octicons-react'
import type {FlashAlert} from '@github-ui/dismissible-flash'
import {useRuleFeatures} from '../hooks/use-rule-features'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {IMPORT_LOCAL_STORAGE_KEY} from '../helpers/constants'

type NewRulesetButtonProps = {
  rulesetsUrl: string
  reloadDocument?: boolean
  defaultEnforcement?: RulesetEnforcement
  sx?: BetterSystemStyleObject
  setFlashAlert: (flashAlert: FlashAlert) => void
}

export const NewRulesetButton: FC<NewRulesetButtonProps> = ({
  rulesetsUrl,
  reloadDocument,
  sx,
  defaultEnforcement = RulesetEnforcement.Disabled,
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  setFlashAlert = () => {},
}) => {
  const [, setImportedRuleset] = useLocalStorage<Ruleset | undefined>(IMPORT_LOCAL_STORAGE_KEY, undefined)
  const {supportedTargets, importExportEnabled} = useRuleFeatures()

  const rulesImportExport = useFeatureFlag('rules_import_export') && importExportEnabled
  const memberPrivilegeRulesetsEnabled = useFeatureFlag('member_privilege_rulesets')
  const lifecycleLabelNameEnabled = isFeatureEnabled('lifecycle_label_name_updates')
  const importExportLocalStorage = useFeatureFlag('rules_import_export_local_storage') && importExportEnabled
  const {navigate} = useRelativeNavigation()
  const [menuOpen, setMenuOpen] = useState(false)

  const actions: ComboButtonAction[] = []

  if (supportedTargets.includes('branch')) {
    actions.push({
      text: 'New branch ruleset',
      href: `${rulesetsUrl}new?target=branch&enforcement=${defaultEnforcement}`,
      reloadDocument,
    })
  }

  if (supportedTargets.includes('tag')) {
    actions.push({
      text: 'New tag ruleset',
      href: `${rulesetsUrl}new?target=tag&enforcement=${defaultEnforcement}`,
      reloadDocument,
    })
  }

  if (supportedTargets.includes('repository')) {
    actions.push({
      text: 'New policy',
      href: `${rulesetsUrl}new?target=repository&enforcement=${defaultEnforcement}`,
      reloadDocument,
    })
  }

  if (supportedTargets.includes('push')) {
    actions.push({
      text: 'New push ruleset',
      href: `${rulesetsUrl}new?target=push&enforcement=${defaultEnforcement}`,
      reloadDocument,
    })
  }

  const jsonUploadUtil = useJsonUpload()

  return rulesImportExport ? (
    <Box sx={{...sx, display: 'flex'}}>
      <ActionMenu open={menuOpen} onOpenChange={() => setMenuOpen(!menuOpen)}>
        <ActionMenu.Anchor>
          <Button variant="primary" trailingAction={TriangleDownIcon}>
            {memberPrivilegeRulesetsEnabled && supportedTargets.includes('repository') ? 'New policy' : 'New ruleset'}
          </Button>
        </ActionMenu.Anchor>
        <ActionMenu.Overlay>
          <ActionList>
            {supportedTargets.includes('branch') && (
              <ActionList.LinkItem
                as={Link}
                to={`${rulesetsUrl}new?target=branch&enforcement=${encodeURI(defaultEnforcement)}`}
                className="text-decoration-skip"
              >
                New branch ruleset
              </ActionList.LinkItem>
            )}
            {supportedTargets.includes('tag') && (
              <ActionList.LinkItem
                as={Link}
                to={`${rulesetsUrl}new?target=tag&enforcement=${defaultEnforcement}`}
                className="text-decoration-skip"
              >
                New tag ruleset
              </ActionList.LinkItem>
            )}
            {supportedTargets.includes('push') && (
              <ActionList.LinkItem
                as={Link}
                className="text-decoration-skip"
                to={`${rulesetsUrl}new?target=push&enforcement=${defaultEnforcement}`}
              >
                New push ruleset
              </ActionList.LinkItem>
            )}
            {memberPrivilegeRulesetsEnabled && supportedTargets.includes('repository') && (
              <ActionList.LinkItem
                as={Link}
                className="text-decoration-skip"
                to={`${rulesetsUrl}new?target=repository&enforcement=${defaultEnforcement}`}
              >
                <Box sx={{whiteSpace: 'nowrap', overflow: 'hidden'}}>New policy</Box>
                <ActionList.TrailingVisual>
                  {lifecycleLabelNameEnabled ? <BetaLabel /> : <Label variant="success">Beta</Label>}
                </ActionList.TrailingVisual>
              </ActionList.LinkItem>
            )}
            <ActionList.Divider />
            <ActionList.Item
              as="button"
              onSelect={jsonUploadUtil.handleUploadIntent}
              disabled={jsonUploadUtil.isUploading}
            >
              <span className="text-normal">Import a ruleset</span>
              <ActionList.Description variant="block" className="no-wrap">
                Choose a JSON file to upload
              </ActionList.Description>
            </ActionList.Item>
            <input
              hidden
              ref={jsonUploadUtil.inputRef}
              type="file"
              accept=".json"
              onChange={async event => {
                try {
                  const importedRuleset = await jsonUploadUtil.handleUpload(event.target.files)
                  if (!importedRuleset) {
                    throw new Error('Cannot import an empty ruleset')
                  }
                  if (importExportLocalStorage) {
                    const navigationResult = await verifiedFetchJSON(`${rulesetsUrl}validate_import`, {
                      method: 'POST',
                      body: importedRuleset,
                    })
                    if (navigationResult.status === 414) {
                      throw new Error(`Error importing ruleset: Query string too long`)
                    }
                    const {message, ruleset} = await navigationResult.json()
                    if (message) {
                      throw new Error(`Error importing ruleset: ${message}`)
                    }
                    setImportedRuleset(ruleset)
                    navigate(`${rulesetsUrl}new`, `imported_ruleset=1&target=${encodeURIComponent(ruleset.target)}`)
                  } else {
                    const navigationResult = await verifiedFetchJSON(
                      `${rulesetsUrl}new?imported_ruleset=${encodeURIComponent(JSON.stringify(importedRuleset))}`,
                      {method: 'GET'},
                    )
                    const result = await navigationResult.json()
                    if (result.errors) {
                      throw new Error(`Error importing ruleset: ${result.errors}`)
                    }
                    navigate(
                      `${rulesetsUrl}new`,
                      `imported_ruleset=${encodeURIComponent(JSON.stringify(importedRuleset))}`,
                    )
                  }
                } catch (error) {
                  setMenuOpen(false)
                  setFlashAlert({message: (error as Error).message || 'Error importing ruleset', variant: 'danger'})
                }
              }}
            />
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </Box>
  ) : (
    <ComboButton actions={actions} ariaLabel="Open ruleset creation menu" />
  )
}

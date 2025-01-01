import type {MouseEvent} from 'react'
import {ControlGroup} from '@github-ui/control-group'
import {BypassSelectPanel} from '@github-ui/bypass-actors/BypassSelectPanel'
import {ActionList, ActionMenu, Link, Text} from '@primer/react'

import Setting from '../SecurityConfiguration/Setting'
import {useAppContext} from '../../contexts/AppContext'
import {useSecuritySettingsContext} from '../../contexts/SecuritySettingsContext'
import {SettingValue} from '../../security-products-enablement-types'
import type {BypassActor} from '@github-ui/bypass-actors/types'
import {BypassList} from '@github-ui/bypass-actors/BypassList'
import {Blankslate} from '@primer/react/experimental'
import {AlertIcon} from '@primer/octicons-react'
import {isShowOnly} from '../../utils/helpers'

import styles from './SecretScanningPushProtection.module.css'
import {clsx} from 'clsx'

const settingStatusLabel = (value: SettingValue) => {
  switch (value) {
    case SettingValue.Enabled:
      return 'Specific actors'
    case SettingValue.Disabled:
      return 'Anyone with write access'
    case SettingValue.NotSet:
      return 'Not set'
  }
}

type SecretScanningPushProtectionProps = {
  initialLevel: 0 | 1
  handleClick?: (name: string) => void
}

const pluralizeActors = (count: number) => `${count === 1 ? 'actor' : 'actors'}`

const SecretScanningPushProtection: React.FC<SecretScanningPushProtectionProps> = ({initialLevel, handleClick}) => {
  const nextLevel = initialLevel === 0 ? 1 : 2
  const {renderContext, helperUrls, securityConfiguration} = useAppContext()
  const {
    secretScanningPushProtection: pushProtectionValue,
    secretScanningDelegatedBypass: delegatedBypassValue,
    secretScanningDelegatedBypassOptions: delegatedByPassOptions,
    handleGhasSettingChange: onChange,
    renderInlineValidation,
  } = useSecuritySettingsContext()
  const bypassReviewers = delegatedByPassOptions?.reviewers || []
  const isShow = isShowOnly(securityConfiguration, renderContext)

  const addBypassActor = (
    actorId: BypassActor['actorId'],
    actorType: BypassActor['actorType'],
    name: BypassActor['name'],
    bypassMode: BypassActor['bypassMode'],
    owner: BypassActor['owner'],
  ) => {
    const reviewers = [...bypassReviewers, {actorId, actorType, name, bypassMode, owner, _enabled: true, _dirty: false}]
    onChange('secretScanningDelegatedBypass', SettingValue.Enabled, {reviewers})
  }

  const removeBypassActor = (bypassActor: BypassActor) => {
    const reviewers = bypassReviewers.filter(
      b => b['actorId'] !== bypassActor['actorId'] || b['actorType'] !== bypassActor['actorType'],
    )
    onChange('secretScanningDelegatedBypass', SettingValue.Enabled, {reviewers})
  }

  const isRepoLevel = renderContext === 'repository' ? true : false
  const renderBypass = renderContext === 'organization'

  const renderActionItem = () => {
    if (isRepoLevel) {
      return securityConfiguration?.enforcement === 'enforced' && pushProtectionValue !== 'not_set' ? (
        <ControlGroup.Custom>{pushProtectionValue === 'enabled' ? 'Enabled' : 'Disabled'}</ControlGroup.Custom>
      ) : (
        <ControlGroup.ToggleSwitch
          aria-labelledby="secret-scanning-push-protection"
          checked={pushProtectionValue === 'enabled'}
          onClick={(e: MouseEvent<HTMLButtonElement>) => {
            e.preventDefault()
            handleClick?.('secretScanningPushProtection')
          }}
        />
      )
    } else {
      return (
        <ControlGroup.Custom>
          <Setting name="secretScanningPushProtection" value={pushProtectionValue} onChange={onChange} />
        </ControlGroup.Custom>
      )
    }
  }

  return (
    <>
      <ControlGroup.Item nestedLevel={initialLevel}>
        <ControlGroup.Title>Push protection</ControlGroup.Title>
        <ControlGroup.Description>
          Block commits that contain supported secrets.
          {renderInlineValidation('secret_scanning_push_protection')}
        </ControlGroup.Description>
        {renderActionItem()}
      </ControlGroup.Item>
      {renderBypass && (
        <ControlGroup.Item nestedLevel={nextLevel}>
          <ControlGroup.Title>Bypass privileges</ControlGroup.Title>
          <ControlGroup.Description>
            Actors with privileges can bypass push protection and approve bypass requests. Bypass privileges can also be
            granted via custom organization roles.{' '}
            <Link inline href={helperUrls?.bypassReviewersRoleUrl}>
              View custom role assignments.
            </Link>
            {renderInlineValidation('secret_scanning_delegated_bypass')}
          </ControlGroup.Description>
          <ControlGroup.Custom>
            {isShow ? (
              <span data-testid={'setting-status'}>{settingStatusLabel(delegatedBypassValue)}</span>
            ) : (
              <ActionMenu>
                <ActionMenu.Button data-testid={'secretScanningDelegatedBypass'}>
                  {settingStatusLabel(delegatedBypassValue)}
                </ActionMenu.Button>
                <ActionMenu.Overlay width="medium">
                  <ActionList selectionVariant="single">
                    <ActionList.Item
                      selected={delegatedBypassValue === SettingValue.Enabled}
                      onSelect={() => onChange('secretScanningDelegatedBypass', SettingValue.Enabled)}
                    >
                      {settingStatusLabel(SettingValue.Enabled)}
                      <ActionList.Description variant="block">
                        Override existing repository settings and enable this feature.
                      </ActionList.Description>
                    </ActionList.Item>

                    <ActionList.Item
                      selected={delegatedBypassValue === SettingValue.Disabled}
                      onSelect={() => onChange('secretScanningDelegatedBypass', SettingValue.Disabled)}
                    >
                      {settingStatusLabel(SettingValue.Disabled)}
                      <ActionList.Description variant="block">
                        Override existing repository settings and disable this feature.
                      </ActionList.Description>
                    </ActionList.Item>

                    <ActionList.Item
                      selected={delegatedBypassValue === SettingValue.NotSet}
                      onSelect={() => onChange('secretScanningDelegatedBypass', SettingValue.NotSet)}
                    >
                      {settingStatusLabel(SettingValue.NotSet)}
                      <ActionList.Description variant="block">
                        Do not override existing repository settings for this feature.
                      </ActionList.Description>
                    </ActionList.Item>
                  </ActionList>
                </ActionMenu.Overlay>
              </ActionMenu>
            )}
          </ControlGroup.Custom>
        </ControlGroup.Item>
      )}
      {delegatedBypassValue === SettingValue.Enabled && renderBypass && helperUrls && !isShow && (
        <>
          <div className={styles.Box}>
            <div className={clsx('Box-header', styles.Box_1)}>
              <Text sx={{}} as="strong">
                {`${bypassReviewers.length || 0} ${pluralizeActors(bypassReviewers.length)}`}
              </Text>
              <BypassSelectPanel
                title={'Select actors'}
                baseAvatarUrl={helperUrls.baseAvatarUrl}
                enabledBypassActors={bypassReviewers}
                addBypassActor={addBypassActor}
                removeBypassActor={removeBypassActor}
                suggestionsUrl={helperUrls.suggestedBypassReviewersUrl}
                addReviewerSubtitle={''}
              />
            </div>
            {bypassReviewers.length > 0 ? (
              <BypassList
                isBypassModeEnabled={false}
                enabledBypassActors={bypassReviewers}
                updateBypassActor={() => {}}
                removeBypassActor={removeBypassActor}
                baseAvatarUrl={helperUrls.baseAvatarUrl}
              />
            ) : (
              <Blankslate>
                <Blankslate.Heading>No actors have been selected</Blankslate.Heading>
              </Blankslate>
            )}
          </div>
          {bypassReviewers.length === 0 && (
            <div className={styles.Box_2}>
              <AlertIcon className="mr-2 border-none fgColor-attention" aria-label="No actors have been selected" />
              <span className={styles.Text}>At least one actor is required.</span>
            </div>
          )}
        </>
      )}
    </>
  )
}

export default SecretScanningPushProtection

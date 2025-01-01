import type {MouseEvent} from 'react'
import {ActionList, ActionMenu, Box, Link as PrimerLink, Text} from '@primer/react'
import {ControlGroup} from '@github-ui/control-group'

import {useAppContext} from '../../contexts/AppContext'
import {useSecuritySettingsContext} from '../../contexts/SecuritySettingsContext'
import {isShowOnly} from '../../utils/helpers'

interface AdvancedSecurityProps {
  handleOnSelectGHAS: (value: string) => void
  handleClick?: (name: string) => void
}

const AdvancedSecurity: React.FC<AdvancedSecurityProps> = ({handleOnSelectGHAS, handleClick}) => {
  const {
    capabilities: {advancedSecurity, actionsAreBilled, ghasFreeForPublicRepos},
    securityConfiguration,
    docsUrls,
    renderContext,
  } = useAppContext()
  const {enableGHAS: enabled, renderInlineValidation} = useSecuritySettingsContext()
  const isShow = isShowOnly(securityConfiguration, renderContext)
  const isRepoLevel = renderContext === 'repository' ? true : false
  const text = enabled ? 'Include' : 'Exclude'
  // In GHES, GHAS is not free for public repos and Actions are not a billable product
  const ghesGhasNotFree = !ghasFreeForPublicRepos && !actionsAreBilled

  const enablementStatus = (
    <ActionMenu>
      <ActionMenu.Button data-testid="enable-ghas-dropdown" id="enable-ghas-button" style={{width: '99px'}}>
        {text}
      </ActionMenu.Button>
      <ActionMenu.Overlay width="medium">
        <ActionList selectionVariant="single">
          <ActionList.Item selected={enabled} onSelect={() => handleOnSelectGHAS('include')}>
            Include
            <ActionList.Description variant="block">
              Enable GitHub Advanced Security for this configuration.{' '}
              {ghesGhasNotFree
                ? 'Applying it will consume licenses.'
                : 'Applying it to private repositories will consume licenses.'}
            </ActionList.Description>
          </ActionList.Item>
          <ActionList.Item selected={!enabled} onSelect={() => handleOnSelectGHAS('exclude')}>
            Exclude
            <ActionList.Description variant="block">
              Disable all GitHub Advanced Security features in this configuration.{' '}
              {ghesGhasNotFree
                ? 'Applying it will not consume licenses.'
                : 'Applying it to private repositories will not consume licenses.'}
            </ActionList.Description>
          </ActionList.Item>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )

  const renderActionItem = () => {
    if (isRepoLevel) {
      return securityConfiguration?.enforcement === 'enforced' ? (
        <ControlGroup.Custom>{text}</ControlGroup.Custom>
      ) : (
        <ControlGroup.ToggleSwitch
          aria-labelledby="advanced_security"
          // checked={!!settingValue}
          onClick={(e: MouseEvent<HTMLButtonElement>) => {
            e.preventDefault()
            handleClick?.('advancedSecurity')
          }}
        />
      )
    } else {
      return <ControlGroup.Custom>{isShow ? text : enablementStatus}</ControlGroup.Custom>
    }
  }

  return (
    advancedSecurity.purchased && (
      <Box sx={{marginY: 4}} data-testid="advanced-security">
        {isRepoLevel && (
          <div style={{marginBottom: 12}}>
            <Text as="strong" sx={{fontSize: 2}}>
              Advanced Security
            </Text>
          </div>
        )}
        <ControlGroup>
          <ControlGroup.Item>
            <ControlGroup.Title as="h3" className="h2-override-shared-component">
              GitHub Advanced Security features
            </ControlGroup.Title>
            <ControlGroup.Description>
              {ghesGhasNotFree
                ? 'Advanced Security features are billed per active committer.'
                : 'Advanced Security features are free for public repositories and billed per active committer in private and internal repositories.'}
              <br />
              <PrimerLink inline href={docsUrls.ghasBilling}>
                Learn more about Advanced Security billing
              </PrimerLink>
              {renderInlineValidation('enable_ghas')}
            </ControlGroup.Description>
            {renderActionItem()}
          </ControlGroup.Item>
        </ControlGroup>
      </Box>
    )
  )
}

export default AdvancedSecurity

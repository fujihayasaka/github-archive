import {ActionMenu, ActionList} from '@primer/react'
import {useState} from 'react'
import {clsx} from 'clsx'
import styles from './CopilotOrganizationGeneralAccessDropdown.module.css'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {useNavigate} from '@github-ui/use-navigate'
import {useNavigation} from '@github-ui/licensing-common/contexts/NavigationContext'

export interface CopilotOrganizationGeneralAccessDropdownProps {
  enablementSetting: string
}

const options = [
  {
    text: 'All organizations',
    value: 'all_organizations',
    subtext: 'Allow access to GitHub Copilot for all organizations, including any created in the future.',
  },
  {
    text: 'Specific organizations',
    value: 'selected_organizations',
    subtext: 'Only specifically-selected organizations may use GitHub Copilot.',
  },
  {
    text: 'Disabled',
    value: 'disabled',
    subtext: 'Disable GitHub Copilot access for all organizations in this enterprise.',
  },
]

export function CopilotOrganizationGeneralAccessDropdown({
  enablementSetting,
}: CopilotOrganizationGeneralAccessDropdownProps) {
  const {basePath} = useNavigation()
  const navigate = useNavigate()
  const [selectedOption, setSelectedOption] = useState<{text: string; value: string}>(() => {
    const initialOption = options.find(option => option.value === enablementSetting)
    return initialOption || {text: 'Disabled', value: 'disabled'}
  })

  const handleOptionChange = async (option: {text: string; value: string}) => {
    const formData = new FormData()
    formData.append('copilot_enabled', option.value)
    try {
      const response = await verifiedFetch(`${basePath}/settings/update_copilot_enablement`, {
        method: 'PUT',
        body: formData,
      })
      if (!response.ok) {
        throw new Error(`${response.status} on ${response.url}`)
      }
      setSelectedOption(option)
      navigate(`${basePath}/enterprise_licensing/copilot`)
    } catch {
      throw new Error('Failed to update organization access settings')
    }
  }

  return (
    <div className={'mb-4'} data-testid="licensing-copilot-access-org-enablement">
      <div className="pb-2">
        <h2>Copilot Access</h2>
      </div>
      <div className={clsx('Box', styles.box, 'p-3', styles.border, styles.positionRelative)}>
        <div className={styles.topRightButton}>
          <ActionMenu>
            <ActionMenu.Button> {selectedOption.text} </ActionMenu.Button>
            <ActionMenu.Overlay style={{minWidth: '300px'}}>
              <ActionList selectionVariant="single">
                {options.map(option => (
                  <ActionList.Item
                    key={option.value}
                    onSelect={() => handleOptionChange(option)}
                    selected={selectedOption.value === option.value}
                    data-testid={`org-item-${option.value.replace('_', '-').toLowerCase()}`}
                  >
                    <span className={clsx(option.value === 'disabled' ? 'color-fg-danger' : 'font-weight-normal')}>
                      {option.text}
                    </span>
                    <p className={'color-fg-muted mt-1'}>{option.subtext}</p>
                  </ActionList.Item>
                ))}
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        </div>
        <h3>Organization access</h3>
        <p className={clsx('color-fg-muted mt-2', styles.textWrap)}>
          Control which organizations will have access to Copilot Business and Copilot Enterprise inside your
          enterprise. Admins of an organization will receive an email with setup instructions.
        </p>
      </div>
    </div>
  )
}

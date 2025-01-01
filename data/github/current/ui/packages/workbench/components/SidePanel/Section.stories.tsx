import {MarkGithubIcon} from '@primer/octicons-react'
import type {Meta} from '@storybook/react'
import {useMemo} from 'react'

import {initialState, WorkbenchStoreContext} from '../../contexts/WorkbenchStoreContext'
import {Section} from './Section'

const meta: Meta<typeof WrappedComponent> = {
  title: 'Apps/Workbench/Components/SidePanel/Section',
  component: Section,
  parameters: {
    enabledFeatures: ['workbench_store_readonly'],
  },
  argTypes: {
    readOnly: {
      control: 'boolean',
      table: {
        category: 'Global',
      },
    },
    onPrimaryActionSelect: {
      action: 'Selected primary action',
      table: {
        disable: true,
      },
    },
    onItemSelect: {
      action: 'Selected item action',
      table: {
        disable: true,
      },
    },
    onSetExpanded: {
      action: 'Toggled item expanded state',
      table: {
        disable: true,
      },
    },
    hasPrimaryAction: {
      control: 'boolean',
      table: {
        category: 'Toggles',
      },
    },
    isExpandable: {
      control: 'boolean',
      table: {
        category: 'Toggles',
      },
    },
    open: {
      control: 'boolean',
      table: {
        category: 'Props',
      },
    },
    loading: {
      control: 'boolean',
      table: {
        category: 'Props',
      },
    },
    title: {
      control: 'text',
      table: {
        defaultValue: {summary: 'Table'},
        category: 'Props',
      },
    },
  },
}

export default meta

const defaultArgs = {
  readOnly: false,
  hasPrimaryAction: false,
  loading: false,
  title: 'Table',
  open: true,
  isExpandable: false,
}

type WrapperComponentProps = typeof defaultArgs & {
  onPrimaryActionSelect: () => void
  onItemSelect: () => void
  onSetExpanded: (value: boolean) => void
}

export const Default = {
  args: defaultArgs,
  render: (args: WrapperComponentProps) => <WrappedComponent {...args} />,
}
const WrappedComponent = ({
  readOnly,
  hasPrimaryAction,
  loading,
  title,
  open,
  isExpandable,
  onPrimaryActionSelect,
  onItemSelect,
  onSetExpanded,
}: WrapperComponentProps) => {
  const workbenchStoreContextValue = useMemo(
    () => ({
      ...initialState,
      hasServiceErrors: false,
      //
      setReadOnly: () => {},
      onError: () => {},
      onConnected: () => {},
      onDisconnected: () => {},
      onIdle: () => {},
      onStatus: () => {},
      onCodespaceStatus: () => {},
      onSuccess: () => {},
      reloadQuota: () => {},
    }),
    [],
  )
  const sectionProps = useMemo(
    () => ({
      readOnly,
      loading,
      title,
      open,
    }),
    [readOnly, loading, title, open],
  )

  return (
    <WorkbenchStoreContext.Provider value={workbenchStoreContextValue}>
      <div className="d-flex flex-justify-center">
        <div style={{width: 420}}>
          <Section {...sectionProps}>
            {hasPrimaryAction && (
              <Section.PrimaryAction icon={MarkGithubIcon} onSelect={onPrimaryActionSelect}>
                Upload file
              </Section.PrimaryAction>
            )}
            <Section.Items>
              {['first', 'second'].map(key => (
                <Section.Item
                  key={key}
                  title={key}
                  description="Lorem ipsum dolor sit amet, consectetur adipiscing elit."
                  icon={MarkGithubIcon}
                  onSelect={onItemSelect}
                  expandable={isExpandable}
                  renderContent={({setIsExpanded}) => (
                    <div>
                      <p>Content for {key}</p>
                      <button
                        onClick={() => {
                          onSetExpanded(false)
                          setIsExpanded(false)
                        }}
                      >
                        Close
                      </button>
                    </div>
                  )}
                />
              ))}
            </Section.Items>
          </Section>
        </div>
      </div>
    </WorkbenchStoreContext.Provider>
  )
}

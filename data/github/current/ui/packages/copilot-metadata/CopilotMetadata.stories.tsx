import {CopilotMetadata} from './CopilotMetadata'

export default {
  title: 'CopilotMetadata',
  component: CopilotMetadata,
}

export const Default = () => (
  <CopilotMetadata
    currentTab="defaultTab"
    setCurrentTab={() => {}}
    loading={false}
    setLoading={() => {}}
    makeCAPIRequest={() => Promise.resolve({data: 'stubbed response'})}
  />
)

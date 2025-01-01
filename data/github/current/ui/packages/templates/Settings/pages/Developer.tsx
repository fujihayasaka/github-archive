import {SettingsLayout} from '../components/SettingsLayout'
import SettingsHeader from '../components/SettingsHeader'
import SectionContent from '../components/SectionContent'
import SectionHeader from '../components/SectionHeader'
import Section from '../components/Section'
import {ControlGroup} from '@github-ui/control-group'
import {AppsIcon, KeyIcon, PersonIcon} from '@primer/octicons-react'
import {Breadcrumbs} from '@primer/react'

import styles from './Developer.module.css'

const Developer = () => {
  return (
    <SettingsLayout active="Developer settings">
      <div className={styles.Box}>
        <Breadcrumbs>
          <Breadcrumbs.Item href="#">Settings</Breadcrumbs.Item>
          <Breadcrumbs.Item href="#" selected>
            Developer
          </Breadcrumbs.Item>
        </Breadcrumbs>
      </div>
      <SettingsHeader title="Developer settings" />
      <Section>
        <SectionContent>
          <ControlGroup fullWidth>
            <ControlGroup.LinkItem href="#" leadingIcon={<AppsIcon />}>
              <ControlGroup.Title as="h2">GitHub apps</ControlGroup.Title>
              <ControlGroup.Description>Create new, manage existing</ControlGroup.Description>
            </ControlGroup.LinkItem>
            <ControlGroup.LinkItem href="#" leadingIcon={<PersonIcon />}>
              <ControlGroup.Title as="h2">OAuth apps</ControlGroup.Title>
              <ControlGroup.Description>Create new, manage existing</ControlGroup.Description>
            </ControlGroup.LinkItem>
          </ControlGroup>
        </SectionContent>
      </Section>
      <Section>
        <SectionHeader title="Personal access tokens" />
        <SectionContent>
          <ControlGroup fullWidth>
            <ControlGroup.LinkItem href="#" leadingIcon={<KeyIcon />}>
              <ControlGroup.Title>Classic tokens</ControlGroup.Title>
            </ControlGroup.LinkItem>
            <ControlGroup.LinkItem href="#" leadingIcon={<KeyIcon />}>
              <ControlGroup.Title>Fine-grained tokens</ControlGroup.Title>
            </ControlGroup.LinkItem>
          </ControlGroup>
        </SectionContent>
      </Section>
    </SettingsLayout>
  )
}

export default Developer

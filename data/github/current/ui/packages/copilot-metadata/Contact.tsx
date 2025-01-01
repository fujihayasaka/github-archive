import {GitHubAvatar} from '@github-ui/github-avatar'
import {Heading, Label, Stack} from '@primer/react'

import styles from './Contact.module.css'
import {Monogram} from './Monogram'
import type {Collaborator} from './types'

export const Contact = ({size = 48, information}: {size?: number; information: Collaborator}) => {
  const defaultAlt = 'User avatar'

  return (
    <div className={styles['contact-container']}>
      {information.avatar_url ? (
        <GitHubAvatar square size={size} src={information.avatar_url} alt={information.username || defaultAlt} />
      ) : (
        <Monogram initials={information.username.charAt(0)} />
      )}
      <div className={styles['contact-info-container']}>
        <Heading as="h2" variant="small">
          {information.username}
        </Heading>
        <Stack direction="horizontal" wrap="wrap">
          <Label key={information.rank}>{information.rank}</Label>
        </Stack>
      </div>
    </div>
  )
}

export const ContactList = ({contacts}: {contacts: Collaborator[]}) => {
  return (
    <div className={styles['contacts-container']}>
      <Heading as="h1" variant="medium">
        Who to talk to
      </Heading>
      <div className={styles['contact-list']}>
        {contacts?.map(contact => <Contact key={contact.id} information={contact} />)}
      </div>
    </div>
  )
}

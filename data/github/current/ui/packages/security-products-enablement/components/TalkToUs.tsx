import {useNavigate} from '@github-ui/use-navigate'
import {Banner} from '@primer/react/experimental'
import {Link as PrimerLink} from '@primer/react'
import {Link} from '@github-ui/react-core/link'

import styles from './TalkToUs.module.css'

interface TalkToUsProps {
  onDismiss: () => void
}

const TalkToUs: React.FC<TalkToUsProps> = ({onDismiss}) => {
  const navigate = useNavigate()
  const bookCall = () => {
    navigate(
      'https://calendar.google.com/calendar/u/0/appointments/schedules/AcZssZ2n3vu9veZadjjWXpH6zCME6xnYQbZETKtrp2GnAFU3eAfQ6jlNQeq4c-3LqCqVjGzUaxl64fn0',
    )
  }

  return (
    <div data-testid="banner-talk-to-us" className={styles.Box}>
      <Banner
        title="Talk to us"
        hideTitle
        onDismiss={onDismiss}
        primaryAction={<Banner.PrimaryAction onClick={bookCall}>Book a call</Banner.PrimaryAction>}
      >
        <Banner.Description>
          We want to make this settings experience amazing for you! Got feedback? Book a call or leave your thoughts in{' '}
          <PrimerLink as={Link} to="https://github.com/orgs/community/discussions/114519" className="Link--inTextBlock">
            a feedback discussion.
          </PrimerLink>
        </Banner.Description>
      </Banner>
    </div>
  )
}

export default TalkToUs

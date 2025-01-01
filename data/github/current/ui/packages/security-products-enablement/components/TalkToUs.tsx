import {useNavigate} from '@github-ui/use-navigate'
import {Banner} from '@primer/react/experimental'
import {Box, Link as PrimerLink} from '@primer/react'
import {Link} from '@github-ui/react-core/link'

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
    <Box sx={{mt: 1, mb: 4}} data-testid="banner-talk-to-us">
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
    </Box>
  )
}

export default TalkToUs

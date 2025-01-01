import {Button} from '@primer/react'
import {Link} from 'react-router-dom'

interface NewConfigurationButtonProps {
  link: string
}

const NewConfigurationButton: React.FC<NewConfigurationButtonProps> = ({link}) => {
  return (
    <Button data-testid="new-configuration" as={Link} to={link} variant="primary">
      New configuration
    </Button>
  )
}

export default NewConfigurationButton

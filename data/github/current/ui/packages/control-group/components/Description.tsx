import {Box, Text} from '@primer/react'

import styles from './Description.module.css'

type DescriptionProps = {
  children: React.ReactNode | string
}

const Description = ({children, ...restProps}: React.HTMLAttributes<HTMLElement> & DescriptionProps) => {
  if (typeof children === 'string') {
    return (
      <Text as="p" className={styles.Text} {...restProps}>
        {children}
      </Text>
    )
  }

  return (
    <Box as="span" className={styles.Box} {...restProps}>
      {children}
    </Box>
  )
}
Description.displayName = 'ControlGroup.Description'

export default Description

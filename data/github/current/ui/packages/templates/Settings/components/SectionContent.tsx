import {Box} from '@primer/react'

import styles from './SectionContent.module.css'

interface SectionContentProps {
  children: React.ReactNode
  variant?: string
  primaryButtonTitle?: string
  secondaryButtonTitle?: string
  isDirty?: boolean
}

const SectionContent = ({variant = 'default', children}: SectionContentProps) => {
  return (
    <>
      {variant === 'form' && <div className={styles.Box}>{children}</div>}
      {variant !== 'form' && (
        <CardContainer>
          <Box
            sx={{
              gap: variant === 'form' ? 3 : 2,
            }}
            className={styles.Box_1}
          >
            {children}
          </Box>
        </CardContainer>
      )}
    </>
  )
}

type CardContainerProps = {
  children: React.ReactNode
  as?: React.ElementType
}

const CardContainer = ({children, as: Component = 'div'}: CardContainerProps) => {
  return <Component className={styles.Box_2}>{children}</Component>
}

export default SectionContent

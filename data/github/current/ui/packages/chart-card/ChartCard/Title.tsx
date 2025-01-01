import {Heading, type SxProp} from '@primer/react'
import {clsx} from 'clsx'
import {useContext, useEffect} from 'react'
import {getNodeText} from '../shared'
import ChartCardContext from './context'

import styles from './Title.module.css'

export type TitleProps = {
  as?: 'h1' | 'h2' | 'h3' | 'h4' | 'h5' | 'h6'
  children: React.ReactNode
  className?: string
} & SxProp

const Title = ({as = 'h3', sx, children, className}: TitleProps) => {
  const {setTitle, size} = useContext(ChartCardContext)
  useEffect(() => {
    setTitle(getNodeText(children))
  }, [setTitle, children])
  return size !== 'sparkline' ? (
    <Heading as={as} sx={sx} className={clsx(className, styles.ChartCardTitleHeading)}>
      {children}
    </Heading>
  ) : null
}

export default Title

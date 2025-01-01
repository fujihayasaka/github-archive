import {Text, type SxProp} from '@primer/react'
import {clsx} from 'clsx'
import {useContext, useEffect} from 'react'
import {getNodeText} from '../shared'
import ChartCardContext from './context'

import styles from './Description.module.css'

export type DescriptionProps = {
  children: React.ReactNode
  className?: string
} & SxProp

const Description = ({sx, children, className}: DescriptionProps) => {
  const {setDescription, size} = useContext(ChartCardContext)
  useEffect(() => {
    setDescription(getNodeText(children))
  }, [setDescription, children])
  return size !== 'sparkline' ? (
    <Text sx={sx} className={clsx(className, styles.ChartCardDescriptionText)}>
      {children}
    </Text>
  ) : null
}

export default Description

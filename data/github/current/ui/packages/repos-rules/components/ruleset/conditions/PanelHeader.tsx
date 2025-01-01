import {Text} from '@primer/react'
import {Pagehead} from '@primer/react/deprecated'
import type {FC} from 'react'
import styles from './PanelHeader.module.css'
import {clsx} from 'clsx'

interface PanelHeaderProps {
  title: string
  subtitle: string
}

export const PanelHeader: FC<PanelHeaderProps> = ({title, subtitle}) => {
  return (
    <>
      <Pagehead className={clsx('h2-override-shared-component', styles.Pagehead)}>{title}</Pagehead>
      <Text sx={{color: 'fg.muted'}}>{subtitle}</Text>
    </>
  )
}

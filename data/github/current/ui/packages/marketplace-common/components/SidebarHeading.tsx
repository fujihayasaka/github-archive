import {Stack, CounterLabel, Link, Text} from '@primer/react'
import styles from './SidebarHeading.module.css'

export interface SidebarHeadingProps {
  title: string
  count?: number
  link?: string
  htmlTag?: keyof JSX.IntrinsicElements
}

export default function SidebarHeading(props: SidebarHeadingProps) {
  const {title, count, link, htmlTag = 'h3'} = props

  return (
    <>
      {link ? (
        <Text as={htmlTag} weight={'semibold'} className={styles.Heading}>
          <Link href={link} className={'Link--primary no-underline'}>
            <Stack gap={'none'} align={'center'} direction={'horizontal'}>
              {title}
              {count ? <CounterLabel className={'ml-1'}>{count}</CounterLabel> : null}
            </Stack>
          </Link>
        </Text>
      ) : (
        <Stack gap={'none'} align={'center'} direction={'horizontal'}>
          <Text as={htmlTag} weight={'semibold'} className={styles.Heading}>
            {title}
          </Text>
          {count ? <CounterLabel className={'ml-1'}>{count}</CounterLabel> : null}
        </Stack>
      )}
    </>
  )
}

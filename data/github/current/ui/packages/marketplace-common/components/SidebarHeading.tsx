import {Stack, CounterLabel, Link, Text} from '@primer/react'

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
        <Text as={htmlTag} weight={'semibold'} sx={{fontSize: [1, 1, 2]}}>
          <Link href={link} className={'Link--primary no-underline'}>
            <Stack gap={'none'} align={'baseline'} direction={'horizontal'}>
              {title}
              {count ? <CounterLabel className={'ml-1'}>{count}</CounterLabel> : null}
            </Stack>
          </Link>
        </Text>
      ) : (
        <Stack gap={'none'} align={'baseline'} direction={'horizontal'}>
          <Text as={htmlTag} weight={'semibold'} sx={{fontSize: [1, 1, 2]}}>
            {title}
          </Text>
          {count ? <CounterLabel className={'ml-1'}>{count}</CounterLabel> : null}
        </Stack>
      )}
    </>
  )
}

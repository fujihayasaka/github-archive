import React from 'react'

import {Box, Heading, type SxProp} from '@primer/react'

export function PageHeading(props: {name: React.ReactNode; description?: React.ReactNode; meta?: React.ReactNode}) {
  return (
    <header className="Subhead">
      <Box
        sx={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          width: '100%',
        }}
      >
        <Heading as="h2" sx={{font: 'var(--text-subtitle-shorthand)'}} className="Subhead-heading">
          {props.name}
        </Heading>
        {props.meta}
      </Box>
      {props.description ? <span className="Subhead-description">{props.description}</span> : null}
    </header>
  )
}

const STACK_GAP_MAPPING = {
  condensed: 'var(--stack-gap-condensed)',
  normal: 'var(--stack-gap-normal)',
  spacious: 'var(--stack-gap-spacious)',
} as const

export function Stack(
  props: React.PropsWithChildren<
    {space?: number | keyof typeof STACK_GAP_MAPPING} & React.HTMLAttributes<HTMLDivElement> & SxProp
  >,
) {
  const {children, sx, space, ...rest} = props
  const items = simpleFlattenChildren(children)

  if (items.length < 2) return <>{items}</>

  let gap: string | number = space ?? 0
  if (typeof space === 'string') gap = STACK_GAP_MAPPING[space] ?? 0

  return (
    <Box
      sx={{
        display: 'flex',
        flexDirection: 'column',
        gap,
        ...sx,
      }}
      {...rest}
    >
      {
        // eslint-disable-next-line @eslint-react/no-children-map
        React.Children.map(items, (child, index) => (
          // eslint-disable-next-line @eslint-react/no-array-index-key
          <div key={index}>{child}</div>
        ))
      }
    </Box>
  )
}

function simpleFlattenChildren(children: React.ReactNode) {
  const kids: React.ReactNode[] = []

  // eslint-disable-next-line github/array-foreach, @eslint-react/no-children-for-each
  React.Children.forEach(children, child => {
    if (React.isValidElement(child)) {
      if (child.type === React.Fragment) {
        kids.concat(simpleFlattenChildren(child.props.children))
        return
      }
      kids.push(child)
    }
  })

  return kids
}

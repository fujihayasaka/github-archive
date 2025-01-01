import {type TestIdProps, testIdProps} from '@github-ui/test-id-props'
import {type BetterSystemStyleObject, Box, Text} from '@primer/react'
import {type ComponentProps, type FC, forwardRef, type ReactNode, type RefObject} from 'react'

export const SidebarFields: FC<{
  listRef: RefObject<HTMLDListElement>
  children: ReactNode
}> = ({children, listRef}) => <dl ref={listRef}>{children}</dl>

export const Field: FC<{label: string; children: React.ReactNode} & TestIdProps> = ({label, children, ...props}) => (
  // div is default for Box, but PRC could change in the future and this is _required_ to be a div by HTML spec
  <Box as="div" sx={{px: 2, py: 1, display: 'flex', gap: 1, flexDirection: 'row', flexWrap: 'wrap'}} {...props}>
    <FieldLabel>{label}</FieldLabel>
    <Box as="dd" sx={{flexBasis: '65%', flexGrow: 1, overflow: 'hidden', minWidth: '200px'}}>
      {children}
    </Box>
  </Box>
)

const FieldLabel: FC<{children: ReactNode}> = ({children}) => (
  <Text
    as="dt"
    sx={{
      px: 2,
      pt: '6px',
      flexBasis: '33%',
      flexGrow: 1,
      flexShrink: 0,
      fontSize: 0,
      fontWeight: 'bold',
      color: 'fg.muted',
    }}
  >
    {children}
  </Text>
)

export const FieldValue: FC<ComponentProps<typeof Box> & {interactable?: boolean}> = forwardRef(
  ({interactable = false, children, sx, ...props}, ref) => {
    const interactStyles: BetterSystemStyleObject = interactable
      ? {cursor: 'pointer', backgroundColor: 'canvas.subtle'}
      : {}

    return (
      <Box
        {...props}
        sx={{
          px: 2,
          py: 1,
          background: 'transparent',
          border: 'none',
          borderRadius: 1,
          ':hover': interactStyles,
          ':focus': interactStyles,
          width: '100%',
          textAlign: 'left',
          ...sx,
        }}
        ref={ref}
        {...testIdProps('field-value')}
      >
        {children}
      </Box>
    )
  },
)
FieldValue.displayName = 'FieldValue'

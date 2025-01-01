import {Stack, Label, Text} from '@primer/react-brand'

export function Topics({topics}: {topics: string[]}) {
  return (
    <Stack direction="horizontal" padding="none" flexWrap="wrap">
      <Text>Tags</Text>
      {topics?.map(topic => <Label key={topic}>{topic}</Label>)}
    </Stack>
  )
}

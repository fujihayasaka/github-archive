import {Label} from '@primer/react'
import {SubtleHeading} from '../traditional/components/Ui'

export default function PreviewFeatureHeading(props: {title: React.ReactNode; beta: boolean}) {
  return (
    <SubtleHeading>
      <span>{props.title}</span>
      {props.beta && (
        <Label variant="success" sx={{marginLeft: 2}}>
          Preview
        </Label>
      )}
    </SubtleHeading>
  )
}

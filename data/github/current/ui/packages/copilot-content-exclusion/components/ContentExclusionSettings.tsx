import React from 'react'
import {ShieldLockIcon} from '@primer/octicons-react'
import {FormControl, Link, Text, Textarea} from '@primer/react'
import type {Rule, ContentExclusionSettingsProps} from '../types'
import {FeedbackLink, PageHeading, Stack} from './Ui'

export function ContentExclusionSettings(props: ContentExclusionSettingsProps) {
  const {locationCopy, applyCopy, entLevelRules, orgLevelRules, children} = props

  return (
    <>
      <PageHeading
        name="Content exclusion"
        meta={
          <>
            <FeedbackLink />
          </>
        }
      />
      <Stack space="normal" data-hpc>
        <p>
          {locationCopy}{' '}
          <Text sx={{fontWeight: 'bold'}}>
            Copilot won’t be able to access or utilize the contents located in those specified paths.{' '}
          </Text>
        </p>
        <p>
          {applyCopy}{' '}
          <Link href="https://gh.io/copilot-content-exclusion" target="_blank" inline>
            Learn more about setup and usage.
          </Link>
        </p>

        {!!entLevelRules && entLevelRules.length > 0 ? (
          <InheritedRules rules={entLevelRules} level="enterprise" />
        ) : null}
        {!!orgLevelRules && orgLevelRules.length > 0 ? (
          <InheritedRules rules={orgLevelRules} level="organization" />
        ) : null}

        {children}
      </Stack>
    </>
  )
}

type InheritedRulesProps = {
  rules: Rule[]
  level: string
}

export function InheritedRules(props: InheritedRulesProps) {
  const {rules = [], level} = props

  function renderRules(rule: Rule, index: number) {
    return (
      <FormControl key={index} disabled>
        <FormControl.Label>
          Excluded paths inherited from {level} <MaybeLink link={rule.link}>{rule.name}</MaybeLink>:
        </FormControl.Label>
        <FormControl.Caption>
          <ShieldLockIcon size="small" /> Values defined by {rule.name}&apos;s administrators can&apos;t be edited
        </FormControl.Caption>
        <Textarea block resize="vertical" rows={4} sx={{fontFamily: 'monospace'}} defaultValue={rule.paths} />
      </FormControl>
    )
  }

  return rules.map(renderRules)
}

function MaybeLink(props: React.PropsWithChildren<{link?: string}>) {
  const {link, ...rest} = props
  if (link) return <Link href={link} inline {...rest} />

  return <React.Fragment {...rest} />
}

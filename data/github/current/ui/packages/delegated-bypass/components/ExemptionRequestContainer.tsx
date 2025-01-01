import {MarkGithubIcon} from '@primer/octicons-react'
import {Box, Heading, RelativeTime, Text, Link, Label} from '@primer/react'
import type {ReactNode, FC} from 'react'
import type {RuleSuite} from '../delegated-bypass-types'

import type {RuleRun} from '@github-ui/repos-rules/types/rules-types'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {ViolationRow} from './ViolationRow'
import {User} from './User'
import {RoundedBox} from './RoundedBox'
import {isFeatureEnabled} from '@github-ui/feature-flags'

type ExemptionRequestContainerProps = {
  children: ReactNode
  ruleSuite: RuleSuite
  displayName?: string
  requestType: string
  requestCompleted?: boolean
  violations?: FC<{ruleRuns: RuleRun[]}>
}

type DropdownInfoProps = {
  ruleRuns: RuleRun[]
  afterOid: string | undefined | null
  violations?: FC<{ruleRuns: RuleRun[]}>
}

export function DropdownInfo({ruleRuns, afterOid, violations}: DropdownInfoProps) {
  if (violations) {
    return violations({ruleRuns})
  }
  return (
    <>
      {ruleRuns.map(ruleRun => {
        return (
          <ViolationRow
            key={ruleRun.id}
            ruleRun={ruleRun}
            afterOid={afterOid}
            sx={{
              borderBottomColor: 'border.default',
              borderBottomWidth: 1,
              borderBottomStyle: 'solid',
            }}
          />
        )
      })}
    </>
  )
}

export function ExemptionRequestContainer({
  children,
  ruleSuite,
  displayName,
  violations,
  requestType,
}: ExemptionRequestContainerProps) {
  const {actor, afterOid, repository, createdAt, ruleRuns} = ruleSuite
  const lifecycleLabelNameEnabled = isFeatureEnabled('lifecycle_label_name_updates')

  return (
    <Box sx={{display: 'flex', flexDirection: 'column', alignItems: 'center', p: 6}}>
      <MarkGithubIcon size={96} />
      <Box sx={{width: '100%', maxWidth: 560}}>
        <Heading
          as="h2"
          sx={{
            mt: 4,
            fontSize: 4,
            textAlign: 'center',
            display: 'flex',
            justifyContent: 'center',
            alignItems: 'center',
          }}
        >
          {displayName ? `${displayName}` : 'Push was blocked'}
          {requestType !== 'secret_scanning' &&
            (lifecycleLabelNameEnabled ? (
              <div className="ml-2">
                <BetaLabel />
              </div>
            ) : (
              <Label sx={{ml: 2}} variant="success">
                Beta
              </Label>
            ))}
        </Heading>
        <RoundedBox sx={{mt: 4}}>
          <Box
            sx={{
              p: 4,
              backgroundColor: 'canvas.subtle',
              gap: 2,
              '> *': {
                py: 2,
                display: 'flex',
                borderColor: 'border.default',
                borderBottomWidth: 1,
                borderBottomStyle: 'solid',
                ':first-child': {
                  pt: 0,
                },
                ':last-child': {
                  borderBottom: 0,
                  pb: 0,
                },
              },
            }}
          >
            <div>
              <Text sx={{color: 'fg.muted', width: '25%'}}>User</Text>
              <Box sx={{width: '75%'}}>{actor ? <User user={actor} /> : 'unknown user'}</Box>
            </div>
            <div>
              <Text sx={{color: 'fg.muted', width: '25%'}}>Repository</Text>
              <Text sx={{width: '75%'}}>
                <Link href={repository.url}>{repository.nameWithOwner}</Link>
              </Text>
            </div>
            {afterOid ? (
              <div>
                <Text sx={{color: 'fg.muted', width: '25%'}}>Commit</Text>
                <Text sx={{width: '75%'}}>{afterOid === 'PENDING' ? 'Pending (from file editor)' : afterOid}</Text>
              </div>
            ) : null}
            <div>
              <Text sx={{color: 'fg.muted', width: '25%'}}>Time</Text>
              <RelativeTime sx={{width: '75%'}} datetime={createdAt.toString()} />
            </div>
          </Box>
          <Box
            sx={{
              '> :last-child': {
                borderBottom: 0,
              },
            }}
          >
            <DropdownInfo ruleRuns={ruleRuns} afterOid={afterOid} violations={violations} />
          </Box>
        </RoundedBox>
        {children}
      </Box>
      {requestType === 'secret_scanning' && (
        <Box sx={{mt: 4}}>
          <Link target="_blank" href="https://github.com/orgs/community/discussions/121816">
            Give feedback
          </Link>
        </Box>
      )}
    </Box>
  )
}

import {assertDataPresent} from '@github-ui/assert-data-present'
import {LinesChangedCounterLabel} from '@github-ui/diff-file-header'
import {Box, Text} from '@primer/react'
import {graphql, useFragment} from 'react-relay'

import {filesChangedHeaderMargin} from '../../helpers/sticky-headers'
import DiffViewSettingsButton from '../DiffViewSettingsButton'
import NavigationPaneToggle from '../NavigationPaneToggle'
import type {FilesChangedHeading_pullRequest$key} from './__generated__/FilesChangedHeading_pullRequest.graphql'
import type {FilesChangedHeading_viewer$key} from './__generated__/FilesChangedHeading_viewer.graphql'

export default function FilesChangedHeading({
  pullRequest,
  viewer,
}: {
  pullRequest: FilesChangedHeading_pullRequest$key
  viewer: FilesChangedHeading_viewer$key
}) {
  const pullRequestData = useFragment(
    graphql`
      fragment FilesChangedHeading_pullRequest on PullRequest {
        ...DiffViewSettingsButton_pullRequest
        comparison(startOid: $startOid, endOid: $endOid, singleCommitOid: $singleCommitOid) {
          linesAdded
          linesDeleted
        }
      }
    `,
    pullRequest,
  )

  const viewerData = useFragment(
    graphql`
      fragment FilesChangedHeading_viewer on User {
        ...DiffViewSettingsButton_user
      }
    `,
    viewer,
  )

  const comparisonData = pullRequestData.comparison
  assertDataPresent(comparisonData)

  return (
    <Box
      sx={{
        backgroundColor: 'canvas.default',
        display: 'flex',
        justifyContent: 'space-between',
        my: 1,
        py: 2,
        px: 3,
        gap: 2,
        position: 'sticky',
        textOverflow: 'ellipsis',
        whiteSpace: 'nowrap',
        top: filesChangedHeaderMargin,
        // Set to ensure that the React.Portal used in Conversations dialog hides behind this header
        zIndex: 11,
        ml: '2px',
      }}
    >
      <Box sx={{alignItems: 'center', display: 'flex', flexDirection: 'row'}}>
        <NavigationPaneToggle sx={{mr: 2}} />
        <Box as="h2" sx={{fontSize: 2, mr: 2, display: 'inline'}}>
          Files changed
        </Box>
        <LinesChangedCounterLabel isAddition>+{comparisonData.linesAdded}</LinesChangedCounterLabel>
        <LinesChangedCounterLabel isAddition={false}>-{comparisonData.linesDeleted}</LinesChangedCounterLabel>
        <Text sx={{fontSize: 0, ml: 2, color: 'fg.muted', whiteSpace: 'nowrap'}}>lines changed</Text>
      </Box>
      <Box sx={{display: 'flex', alignItems: 'center', gap: 0, ml: 3}}>
        {/* TODO: work in a non-relay version of copilot diff chat from ui/packages/copilot-code-chat */}
        <DiffViewSettingsButton pullRequest={pullRequestData} user={viewerData} />
      </Box>
    </Box>
  )
}

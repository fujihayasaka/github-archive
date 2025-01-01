import {CopilotIcon} from '@primer/octicons-react'
import {Box} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {testIdProps} from '@github-ui/test-id-props'

export function CopilotSummarizeBannerPlaceholder({hide}: {hide?: boolean | null}) {
  return (
    <Box
      sx={{
        display: hide ? 'none' : 'flex',
        flexDirection: 'row',
        width: '100%',
        px: 2,
        pt: 2,
        pb: 2,
        pl: 3,
        pr: 3,
        alignItems: 'center',
        justifyContent: 'space-between',
        backgroundColor: 'canvas.subtle',
        mb: 3,
        borderRadius: 2,
        borderColor: 'border.default',
        borderStyle: 'solid',
        borderWidth: 1,
        gap: 2,
      }}
      {...testIdProps('copilot-summarize-banner-placeholder')}
    >
      <span className="d-flex flex-1 flex-items-center gap-2" style={{margin: '0.125rem 0'}}>
        <div
          className="circle"
          style={{
            width: '24px',
            height: '24px',
            backgroundColor: 'var(--bgColor-default)',
            border: '1px solid var(--borderColor-default)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          <Octicon
            icon={CopilotIcon}
            size={12}
            sx={{
              color: 'fg.default',
            }}
          />
        </div>
        <span
          style={{
            fontWeight: 600,
          }}
        >
          Copilot
        </span>
        <span className="d-flex flex-1">
          <span
            className="Skeleton Skeleton--text"
            style={{width: '60%', backgroundColor: 'var(--bgColor-neutral-muted)'}}
          >
            &nbsp;
          </span>
        </span>
      </span>
    </Box>
  )
}

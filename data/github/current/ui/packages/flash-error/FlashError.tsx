import {XCircleFillIcon} from '@primer/octicons-react'
import {Box, Flash, Link} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {UnsafeHTMLText} from '@github-ui/safe-html/UnsafeHTML'

export function FlashError({
  prefix,
  errorMessageUsingPrefix,
  errorMessageNotUsingPrefix,
  hideRuleErrorsTitle,
  ruleErrors,
  helpUrl,
  flashRef,
}: {
  prefix: string
  errorMessageUsingPrefix?: string
  errorMessageNotUsingPrefix?: string
  hideRuleErrorsTitle?: boolean
  ruleErrors?: string[]
  helpUrl?: string
  flashRef?: React.RefObject<HTMLDivElement>
}) {
  const isRuleViolation = (ruleErrors?.length || 0) > 0

  return errorMessageUsingPrefix || errorMessageNotUsingPrefix ? (
    <>
      <Flash
        id="flash"
        variant="danger"
        className="d-flex flex-items-center flex-justify-between"
        sx={{marginBottom: 3}}
        tabIndex={-1}
        ref={flashRef}
      >
        {errorMessageUsingPrefix ? (
          <div>
            {prefix} <UnsafeHTMLText sx={{fontWeight: 'bold'}} html={errorMessageUsingPrefix} />
            {isRuleViolation && helpUrl && (
              <Link
                href={`${helpUrl}/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets`}
                sx={{marginLeft: 1}}
              >
                Learn more about rulesets.
              </Link>
            )}
          </div>
        ) : (
          errorMessageNotUsingPrefix && <div>{errorMessageNotUsingPrefix}</div>
        )}
      </Flash>
      {isRuleViolation && (
        <Box sx={{marginBottom: 3}}>
          {!hideRuleErrorsTitle && (
            <Box sx={{fontWeight: 'bold', marginBottom: 1}}>Repository rule violations found:</Box>
          )}
          {ruleErrors?.map(rule => (
            <Box key={rule} sx={{display: 'flex', alignItems: 'center'}}>
              <Octicon icon={XCircleFillIcon} size={16} sx={{color: 'danger.fg'}} />
              <Box sx={{marginLeft: 2}}>{rule}</Box>
            </Box>
          ))}
        </Box>
      )}
    </>
  ) : null
}

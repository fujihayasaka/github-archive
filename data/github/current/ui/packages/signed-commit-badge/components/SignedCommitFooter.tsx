import {Box, Label, Link, Text, RelativeTime} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {InfoIcon} from '@primer/octicons-react'
import type {CommitSignatureType} from '../signed-commit-types'
import {GitHubAvatar} from '@github-ui/github-avatar'

export type Signer = {
  login: string
  avatar_url: string
}

export default function SignedCommitFooter({
  keyHex,
  signatureType,
  signer,
  verifiedAt,
  showPartiallyVerifiedMessage,
  signingLinkComponent,
  keyExpired,
  keyRevoked,
}: {
  /** The hex fingerprint of the SSH key or the GPG key id */
  keyHex: string
  signatureType: CommitSignatureType
  signer: Signer | undefined
  verifiedAt: string | undefined
  showPartiallyVerifiedMessage: boolean
  signingLinkComponent: JSX.Element
  keyExpired: boolean
  keyRevoked: boolean
}) {
  const keyLabel = signatureType === 'SshSignature' ? 'SSH Key Fingerprint:' : 'GPG Key ID:'
  const keyName = signatureType === 'SshSignature' ? 'SSH' : 'GPG'
  return (
    <Box sx={{display: 'flex'}} data-testid="signed-commit-footer">
      <Box
        sx={{
          fontSize: 0,
          flexGrow: 1,
          maxWidth: '100%',
        }}
      >
        {showPartiallyVerifiedMessage && signer ? (
          <>
            <Box sx={{py: 3}}>
              <Box sx={{display: 'flex'}}>
                <GitHubAvatar src={signer.avatar_url} size={20} sx={{mr: 2, ml: 3}} />
                <Box sx={{flex: 1}}>
                  <Link href={`/${signer.login}`} sx={{fontSize: 0, color: 'fg.default', fontWeight: 'bold'}}>
                    {signer.login}
                  </Link>
                  <span>&apos;s contribution has been verified via {keyName} key.</span>
                </Box>
              </Box>
            </Box>
            <Box
              sx={{
                backgroundColor: 'attention.subtle',
                display: 'flex',
                p: 3,
              }}
            >
              <Octicon icon={InfoIcon} sx={{mr: 2}} />
              We cannot verify signatures from co-authors, and some of the co-authors attributed to this commit require
              their commits to be signed.
            </Box>
          </>
        ) : (
          <>
            {signer && signer.login ? (
              <Box sx={{px: 3, pt: 3}} data-testid="github-user-data">
                <>
                  <GitHubAvatar src={signer.avatar_url} size={20} sx={{mr: 2}} />
                  <Link href={`/${signer.login}`} sx={{fontSize: 1, color: 'fg.default', fontWeight: 'bold'}}>
                    {signer.login}
                  </Link>
                </>
              </Box>
            ) : (
              <></>
            )}
            <Box sx={{p: 3, flexDirection: 'column'}}>
              {keyHex && (
                <div>
                  {keyLabel} <Text sx={{color: 'fg.muted'}}>{keyHex}</Text>
                </div>
              )}
              {verifiedAt && (
                <div>
                  Verified{' '}
                  <RelativeTime datetime={verifiedAt} threshold="PT0S" year="numeric" hour="2-digit" minute="2-digit" />
                </div>
              )}
              {keyHex && (keyExpired || keyRevoked) && (
                <Box sx={{py: 1}}>
                  {keyExpired && (
                    <Label sx={{mr: 1}} variant="accent">
                      Expired
                    </Label>
                  )}
                  {keyRevoked && <Label variant="attention">Revoked</Label>}
                </Box>
              )}
              {signingLinkComponent}
            </Box>
          </>
        )}
      </Box>
    </Box>
  )
}

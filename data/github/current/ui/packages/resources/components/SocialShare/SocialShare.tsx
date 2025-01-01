import {LinkIcon} from '@primer/octicons-react'
import {AnimationProvider, Animate, Text, Box, Stack} from '@primer/react-brand'
import {useState} from 'react'
import Facebook from './logos/Facebook'
import TwitterX from './logos/TwitterX'
import LinkedIn from './logos/LinkedIn'
import style from './SocialShare.module.css'

const CopyClip = () => (
  <AnimationProvider>
    <Animate>
      <Box padding="condensed" borderWidth="thin">
        <Text className={style.copyText} variant="muted" size="100">
          Link copied to clipboard
        </Text>
      </Box>
    </Animate>
  </AnimationProvider>
)

export const SocialShare = ({url}: {url: string}) => {
  const [copied, setCopied] = useState(false)
  const copyToClipboard = () => {
    navigator.clipboard.writeText(url)
    setCopied(true)
    setTimeout(() => setCopied(false), 4000)
  }

  return (
    <Stack direction="horizontal" padding="none" justifyContent="space-between">
      <Text>Share</Text>
      <div className="d-flex flex-items-center">
        <div className="position-relative">
          <button onClick={copyToClipboard} className={`ml-3 ${style.copyLink} ${style.socialLink}`}>
            <LinkIcon size={16} />
            <Text as="span" className="sr-only">
              Copy link to share
            </Text>
          </button>

          <div aria-live="polite" className="position-absolute bottom-0">
            {copied && <CopyClip />}
          </div>
        </div>

        <a
          href={`https://www.facebook.com/sharer/sharer.php?u=${url}`}
          className={`${style.socialLink} d-flex flex-items-center ml-3`}
          rel="noopener noreferrer"
        >
          <Text as="span" className="sr-only">
            Share on Facebook
          </Text>
          <Facebook />
        </a>
        <a
          href={`https://x.com/intent/tweet?url=${url}`}
          className={`${style.socialLink} d-flex flex-items-center ml-3`}
          rel="noopener noreferrer"
        >
          <Text as="span" className="sr-only">
            Share on X
          </Text>
          <TwitterX />
        </a>
        <a
          href={`https://www.linkedin.com/shareArticle?mini=true&url=${url}`}
          className={`${style.socialLink} d-flex flex-items-center ml-3`}
          rel="noopener noreferrer"
        >
          <Text as="span" className="sr-only">
            Share on LinkedIn
          </Text>
          <LinkedIn />
        </a>
      </div>
    </Stack>
  )
}

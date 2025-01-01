import {CircleOcticon, Link} from '@primer/react'
import type {Icon} from '@primer/octicons-react'
import {testIdProps} from '@github-ui/test-id-props'
import styles from './GetStartedBox.module.css'

interface GetStartedBoxProps {
  href?: string
  callToAction: string
  onClick?: () => void
  icon: Icon
}

export function GetStartedBox({href, callToAction, icon: LeftIcon, onClick}: GetStartedBoxProps) {
  const content = (
    <>
      <div className="d-flex flex-items-center flex-xl-items-start flex-row flex-xl-column flex-1">
        <CircleOcticon
          icon={() => <LeftIcon size={24} {...testIdProps('get-started-icon')} />}
          className="fgColor-muted bgColor-muted"
          size={32}
        />
      </div>
      <span className="f4 color-fg-default text-semibold py-3">{callToAction}</span>
    </>
  )

  return (
    <>
      {href ? (
        <Link href={href} className={`pt-xl-4 flex-xl-column flex-xl-items-start ${styles.getStartedBox}`}>
          {content}
        </Link>
      ) : onClick ? (
        <button
          type="button"
          className={`flex-1 bgColor-default border rounded-2 px-4 py-xl-4 d-flex flex-row flex-xl-column flex-items-center flex-xl-items-start flex-justify-between ${styles.getStartedBox}`}
          {...testIdProps('get-started-box-button')}
          onClick={onClick}
        >
          {content}
        </button>
      ) : null}
    </>
  )
}

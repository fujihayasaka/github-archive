import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {
  CheckCircleFillIcon,
  CheckIcon,
  DotFillIcon,
  IdBadgeIcon,
  LinkExternalIcon,
  LockIcon,
  RocketIcon,
  SyncIcon,
  XCircleIcon,
} from '@primer/octicons-react'
import {ActionList, ActionMenu, AnchoredOverlay, Button, Label, Link, Spinner} from '@primer/react'
import {useCallback, useState} from 'react'

import {usePublishingContext} from '../../contexts/PublishingContext'
import type {DeploymentVisibility} from '../../types/deployment-types'
import {SparkleSpinner} from '../SparkleSpinner'
import styles from './PublishDropdown.module.css'

const DeploymentVisibilityOptions: Record<
  DeploymentVisibility,
  {title: string; description: string; icon: React.ReactElement}
> = {
  only_owner: {
    title: 'Only you',
    description: 'Private no matter what',
    icon: <LockIcon />,
  },
  github: {
    title: 'All GitHub users',
    description: 'Anyone with the link who is signed into github.com',
    icon: <IdBadgeIcon />,
  },
}

const getPublishingText = (publishingStatus: string) => {
  switch (publishingStatus) {
    case 'publishingFirstTime':
    case 'republishing':
      return 'Publishing'
    case 'publishedFirstTime':
    case 'published':
    case 'republishFailed':
      return 'Published'
    case 'unpublished':
    default:
      return 'Publish'
  }
}

const getButtonIcon = (publishingStatus: string) => {
  switch (publishingStatus) {
    case 'publishingFirstTime':
    case 'republishing':
      return <Spinner size="small" />
    case 'publishedFirstTime':
    case 'published':
    case 'republishFailed':
      return <DotFillIcon size="small" className="fgColor-success" />
    case 'unpublished':
    default:
      return null
  }
}

interface PublishDropdownProps {
  className?: string
  variant?: 'menu' | 'button'
}

export const PublishDropdown = ({className, variant = 'button'}: PublishDropdownProps) => {
  const [menuOpen, setMenuOpen] = useState(false)
  const [showUpdated, setShowUpdated] = useState(false)
  const {
    publishingStatus,
    publishedUrl,
    startDeploymentPipeline,
    canCurrentlyPublish,
    isPublishUpToDate,
    visibility,
    setVisibility: setRawVisibility,
    unpublish,
    cancelPublishing,
  } = usePublishingContext()

  const setVisibility = useCallback(
    (vis: DeploymentVisibility) => {
      setRawVisibility(vis)
      setShowUpdated(true)
      setTimeout(() => {
        setShowUpdated(false)
      }, 2000)
    },
    [setRawVisibility],
  )

  return (
    <AnchoredOverlay
      open={menuOpen && publishingStatus !== 'unpublished'}
      onOpen={() => {
        setMenuOpen(true)
        if (publishingStatus === 'unpublished') {
          startDeploymentPipeline()
        }
      }}
      onClose={() => setMenuOpen(false)}
      renderAnchor={props => {
        if (variant === 'menu') {
          return (
            <ActionList.Item
              {...props}
              className={className}
              role="menuitem"
              disabled={!canCurrentlyPublish && publishingStatus === 'unpublished'}
            >
              <ActionList.LeadingVisual>
                {publishingStatus === 'unpublished' ? <RocketIcon /> : getButtonIcon(publishingStatus)}
              </ActionList.LeadingVisual>
              {getPublishingText(publishingStatus)}
            </ActionList.Item>
          )
        }

        return (
          <Button
            {...props}
            className={className}
            variant={publishingStatus === 'unpublished' ? 'primary' : 'default'}
            disabled={!canCurrentlyPublish && publishingStatus === 'unpublished'}
            leadingVisual={getButtonIcon(publishingStatus)}
          >
            {getPublishingText(publishingStatus)}
          </Button>
        )
      }}
      width="large"
      preventOverflow={false}
    >
      <div className={styles.overlayWrapper}>
        <div className="p-3 flex-1">
          {publishingStatus === 'publishingFirstTime' || publishingStatus === 'publishedFirstTime' ? (
            <div className={styles.publishState}>
              {publishingStatus === 'publishingFirstTime' ? (
                <SparkleSpinner />
              ) : (
                <CheckCircleFillIcon size={24} className="fgColor-success" />
              )}
              <h2 className="mt-2 f4 text-bold">
                {publishingStatus === 'publishingFirstTime' ? 'Sending bytes to the moon' : 'Success!'}
              </h2>
              {publishingStatus === 'publishedFirstTime' && (
                <p className="mt-1 mb-0 fgColor-muted text-center text-balance">
                  <span>
                    Published your spark to <span className="wb-break-word">{publishedUrl}</span>
                  </span>
                </p>
              )}
            </div>
          ) : (
            <div>
              <div className="d-flex flex-items-center flex-justify-between flex-wrap-reverse gap-2">
                <div className="d-flex flex-items-center gap-2">
                  <Link href={publishedUrl} className="wb-break-word">
                    {publishedUrl}
                  </Link>
                  {publishedUrl && <CopyToClipboardButton textToCopy={publishedUrl} size="small" />}
                </div>
                <div className="d-flex flex-items-center gap-1">
                  {publishingStatus === 'published' ? (
                    <>
                      <DotFillIcon size={16} className="fgColor-success" />
                      <span className="f6 white-space-nowrap">Live</span>
                      {isPublishUpToDate === false ? (
                        <Label variant="attention" size="small">
                          Outdated
                        </Label>
                      ) : null}
                    </>
                  ) : publishingStatus === 'republishFailed' ? (
                    <>
                      <XCircleIcon size={16} className="fgColor-danger" />
                      <span className="f6">Publishing failed</span>
                    </>
                  ) : (
                    <>
                      <SparkleSpinner size="small" />
                      <span className="f6">Updating</span>
                    </>
                  )}
                </div>
              </div>
              <div className="mt-3">
                <h3 className="f5 text-bold m-0">Visibility</h3>
                <p className="note m-0 mb-2">Choose who can view your spark</p>
                <div className="d-flex flex-items-center flex-wrap gap-2">
                  <ActionMenu>
                    <ActionMenu.Button leadingVisual={DeploymentVisibilityOptions[visibility]?.icon}>
                      {DeploymentVisibilityOptions[visibility]?.title}
                    </ActionMenu.Button>
                    <ActionMenu.Overlay width="medium">
                      <ActionList selectionVariant="single">
                        {Object.entries(DeploymentVisibilityOptions).map(([key, option]) => (
                          <ActionList.Item
                            key={key}
                            onSelect={() => setVisibility(key as DeploymentVisibility)}
                            selected={visibility === key}
                          >
                            <ActionList.LeadingVisual>{option.icon}</ActionList.LeadingVisual>
                            {option.title}
                            <ActionList.Description variant="block">{option.description}</ActionList.Description>
                          </ActionList.Item>
                        ))}
                      </ActionList>
                    </ActionMenu.Overlay>
                  </ActionMenu>
                  {showUpdated && <CheckIcon className="fgColor-success" />}
                </div>
                {publishingStatus === 'published' && visibility === 'github' && (
                  <p className="mt-2 mb-0 f6 fgColor-muted">
                    Anyone with the link can see all of this spark’s contents and data. Be careful with sensitive
                    information.
                  </p>
                )}
              </div>
            </div>
          )}
        </div>
        <div className={styles.overlayFooter}>
          {publishingStatus === 'publishingFirstTime' || publishingStatus === 'republishing' ? (
            <Button variant="danger" onClick={cancelPublishing}>
              Cancel
            </Button>
          ) : (
            <Button variant="danger" disabled onClick={unpublish}>
              Unpublish
            </Button>
          )}
          <div className="d-flex flex-items-center gap-2 flex-wrap-reverse">
            <Button
              leadingVisual={SyncIcon}
              onClick={startDeploymentPipeline}
              disabled={
                (publishingStatus !== 'published' && publishingStatus !== 'republishFailed') || !canCurrentlyPublish
              }
            >
              Update
            </Button>

            <Button trailingVisual={LinkExternalIcon} variant="primary" as="a" href={publishedUrl} target="_blank">
              View site
            </Button>
          </div>
        </div>
      </div>
    </AnchoredOverlay>
  )
}

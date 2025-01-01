import {Button, type ButtonProps, CounterLabel} from '@primer/react'
import {useCallback, useState, useMemo} from 'react'
import {StarFillIcon, StarIcon} from '@primer/octicons-react'
import {verifiedFetch} from '@github-ui/verified-fetch'
import styles from '../../marketplace.module.css'
import {marketplaceActionPath, repositoryPath} from '@github-ui/paths'
import type {Repository, StarData} from '../../types'
import type {ActionListing} from '@github-ui/marketplace-common'
import {sendEvent} from '@github-ui/hydro-analytics'
import {Tooltip} from '@primer/react/next'

interface StarButtonProps extends Omit<ButtonProps, 'onClick' | 'leadingIcon' | 'children'> {
  repository: Repository
  action: ActionListing
  loggedIn: boolean
  starData: StarData
}

export function StarButton(props: StarButtonProps) {
  const {repository, action, loggedIn, starData, ...buttonProps} = props
  const {starredByCurrentUser, currentUserAbleToStar, currentUserEnterpriseName} = starData

  const unableToStarText = currentUserEnterpriseName
    ? `You cannot star repositories outside of your enterprise ${currentUserEnterpriseName}`
    : "You can't star at this time"

  const [currentStarCount, setCurrentStarCount] = useState(action.stars)
  const [currentlyStarred, setCurrentlyStarred] = useState(starredByCurrentUser)

  const star = useCallback(
    () =>
      // repository owner and name will be present
      verifiedFetch(`${repositoryPath({owner: repository.owner || '', repo: repository.name || ''})}/star`, {
        method: 'POST',
      }),
    [repository.name, repository.owner],
  )
  const unstar = useCallback(
    () =>
      // repository owner and name will be present
      verifiedFetch(`${repositoryPath({owner: repository.owner || '', repo: repository.name || ''})}/unstar`, {
        method: 'POST',
      }),
    [repository.name, repository.owner],
  )

  const formattedStarCount = useMemo(() => {
    if (currentStarCount >= 1000) {
      return new Intl.NumberFormat('en-US', {
        notation: 'compact',
        compactDisplay: 'short',
        maximumFractionDigits: 1,
      }).format(currentStarCount)
    }
    return currentStarCount.toString()
  }, [currentStarCount])

  const handleStarring = useCallback(async () => {
    const eventTarget = currentlyStarred ? 'UNSTAR_BUTTON' : 'STAR_BUTTON'
    sendEvent('repository.click', {target: eventTarget, repository_id: repository.id})

    const performAction = currentlyStarred ? unstar : star
    setCurrentlyStarred(!currentlyStarred)

    const res = await performAction()
    if (!res.ok) {
      // Starring failed, so revert back to the previous state
      setCurrentlyStarred(currentlyStarred)
      return
    }
    if (currentlyStarred) {
      setCurrentStarCount(currentStarCount - 1)
    } else {
      setCurrentStarCount(currentStarCount + 1)
    }
  }, [currentlyStarred, star, unstar, currentStarCount, repository.id])

  const isComponentRenderable = repository.owner && repository.name && action.slug
  if (!isComponentRenderable) {
    return null
  }

  return loggedIn && (currentUserAbleToStar || currentlyStarred) ? (
    // fully functional star button when user is logged in and able to star
    <Button
      onClick={handleStarring}
      leadingVisual={
        currentlyStarred ? (
          <StarFillIcon className={currentlyStarred ? `${styles['starred-button-icon']}` : ''} />
        ) : (
          StarIcon
        )
      }
      aria-label={
        currentlyStarred
          ? `Unstar this repository (${formattedStarCount})`
          : `Star this repository (${formattedStarCount})`
      }
      data-testid="star-button"
      {...buttonProps}
    >
      {currentlyStarred ? 'Starred' : 'Star'}
      <CounterLabel className="ml-2">{formattedStarCount}</CounterLabel>
    </Button>
  ) : loggedIn ? (
    // disabled star button when user is logged in but unable to star
    <Tooltip text={unableToStarText}>
      <Button inactive leadingVisual={StarIcon} data-testid="star-button" {...buttonProps}>
        Star
        <CounterLabel className="ml-2">{formattedStarCount}</CounterLabel>
      </Button>
    </Tooltip>
  ) : (
    // sign in star button when user is not logged in
    <Tooltip text="You must be signed in to star a repository">
      <Button
        as="a"
        leadingVisual={StarIcon}
        href={`/login?return_to=${encodeURIComponent(marketplaceActionPath({slug: action.slug || ''}))}`} // action slug will be present
        onClick={() =>
          sendEvent('authentication.click', {
            location_in_page: 'star button',
            repository_id: repository.id,
            auth_type: 'LOG_IN',
          })
        }
        data-testid="star-button"
        {...buttonProps}
      >
        Star
        <CounterLabel className="ml-2">{formattedStarCount}</CounterLabel>
      </Button>
    </Tooltip>
  )
}

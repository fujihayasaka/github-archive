import type {Repository} from '@github-ui/current-repository'
import {ownerPath, repositoryPath} from '@github-ui/paths'
import {CheckIcon, DotFillIcon, LinkExternalIcon, XIcon} from '@primer/octicons-react'
import {ActionMenu, Breadcrumbs, Button, Stack} from '@primer/react'

import styles from './DeployButton.module.css'

interface DeployButtonProps {
  repo: Repository
  description: string
  buildStatus: 'success' | 'failure' | 'pending'
  deployStatus: 'success' | 'failure' | 'pending'
  deployUrl: string
  onDeploymentStart: () => void
  isDeploying: boolean
}

export const DeployButton = ({
  repo,
  description,
  deployStatus,
  buildStatus,
  deployUrl,
  onDeploymentStart,
  isDeploying,
}: DeployButtonProps) => {
  const repoHref = repositoryPath({owner: repo.ownerLogin, repo: repo.name})
  const ownerHref = ownerPath({owner: repo.ownerLogin})

  return (
    <ActionMenu>
      {deployStatus === 'success' && buildStatus === 'success' ? (
        <ActionMenu.Button
          trailingAction={undefined}
          onClick={onDeploymentStart}
          leadingVisual={
            <div style={{fill: 'var(--fgColor-success)'}}>
              <DotFillIcon size={16} className={styles.successIcon} />
            </div>
          }
        >
          Deployed
        </ActionMenu.Button>
      ) : !isDeploying ? (
        <ActionMenu.Button variant="primary" trailingAction={undefined} onClick={onDeploymentStart}>
          Deploy
        </ActionMenu.Button>
      ) : (
        <ActionMenu.Button variant="primary" trailingAction={undefined}>
          Deploying...
        </ActionMenu.Button>
      )}
      <ActionMenu.Overlay>
        <div className={styles.container}>
          {/* Header */}
          <section className={styles.section}>
            <Stack direction="horizontal" align="center">
              {/* Left header */}
              <Breadcrumbs className={styles.breadcrumbs}>
                <Breadcrumbs.Item className={styles.breadcrumbs} href={ownerHref}>
                  {repo.ownerLogin}
                  {/* Repo owner */}
                </Breadcrumbs.Item>
                <Breadcrumbs.Item className={styles.breadcrumbs} href={repoHref}>
                  {repo.name}
                  {/* Repo name */}
                </Breadcrumbs.Item>
              </Breadcrumbs>
              {/* Right header */}
              {deployStatus === 'success' && (
                <>
                  <div style={{marginLeft: 'auto', fill: 'var(--fgColor-success)'}}>
                    <DotFillIcon size={16} className={styles.successIcon} />
                  </div>
                  <p>Live</p>
                </>
              )}
            </Stack>

            {/* Description */}
            <p className={styles.description}>{description}</p>
          </section>

          {/* Statuses */}
          <section className={`${styles.section} ${styles.statusSection}`}>
            <Stack direction="horizontal" align="center">
              {buildStatus === 'success' ? (
                <CheckIcon className={styles.successIcon} />
              ) : buildStatus === 'failure' ? (
                <XIcon className={styles.failureIcon} />
              ) : (
                <DotFillIcon className={styles.pendingIcon} />
              )}
              <p className={styles.statusTitle}>Build the Spark</p>
              <p className={styles.statusInfo}>
                {repo.ownerLogin}/{repo.name}
              </p>
            </Stack>
            <Stack direction="horizontal" align="center">
              {deployStatus === 'success' ? (
                <CheckIcon className={styles.successIcon} />
              ) : deployStatus === 'failure' ? (
                <XIcon className={styles.failureIcon} />
              ) : (
                <DotFillIcon className={styles.pendingIcon} />
              )}
              <p className={styles.statusTitle}>Deploy the site</p>
              <p className={styles.statusInfo}>{deployUrl}</p>
            </Stack>
          </section>

          {/* Buttons */}
          {buildStatus === 'success' && deployStatus === 'success' && (
            <section className={`${styles.section} ${styles.buttonsSection}`}>
              <Stack direction="horizontal" align="center">
                <Button variant="danger" style={{marginRight: 'auto'}}>
                  Delete
                </Button>
                <Button>Manage</Button>
                <Button trailingVisual={LinkExternalIcon} variant="primary" as="a" href={deployUrl} target="_blank">
                  View site
                </Button>
              </Stack>
            </section>
          )}
        </div>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}

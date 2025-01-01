# Nomad Config Changes

If environment variables needed for any Launch services have changed, config files need to be updated. We use Kubernetes config files in this repository for Proxima, Lab, and Production - those should be updated with your pull request.

For GHES, the Nomad config files need to be updated.

## GHES

1. Run the `sha-sync` chatops for launch (https://github.com/github/c2c-actions/blob/main/docs/ghes/updating-images.md#how-to-launch)
1. Update the GHES Nomad config (https://github.com/github/enterprise2/tree/master/vm_files/etc/consul-templates/etc/nomad-jobs/launch)

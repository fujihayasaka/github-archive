# Manually Scaling Deployments

Occasionally, you may need to manually scale a deployment up or down. Most frequently, this will be due to the need to halt all of a certain deployment type (usually hydro processors or aqueduct workers) to perform some maintenance, then restore it back to its original state.

## Steps

1. Login to an ops shell
2. Login to vault
3. Configure kubernetes access

```
$ ssh shell.service.ac4-iad.github.net -J bastion.githubapp.com

({user}@bastion.githubapp.com) Follow the link for FIDO authentication and then submit a blank password:
https://fido-challenger.githubapp.com/challenges/{uuid}
Password:

$ . vault-login

Hello, {user}.
github.com password:
FIDO authentication required for vault. Follow the link to authorize.
https://fido-challenger.githubapp.com/challenges/{uuid}
Login succeeded. VAULT_TOKEN has been set in your environment.
Successfully authenticated. Your vault token has been set in the environment.

$ gh-kubeconfig

configured access to:
List of kube regions
```

4. Run the kubectl scale command, supplying it with the deployment name, the cluster name, and the desired number of replicas.

The stamp name (prefixed with `licensify-`) and list of available clusters in that stamp can be found in the devportal at https://devportal.githubapp.com/devportal/apps/licensify?tab=deployenvs.

![Screenshot of devportal deployments](https://github.com/user-attachments/assets/acda3b52-d633-4fe9-a2ac-b59727e4f479)

To scale down all hosts for a deployment in a stamp, repeat the following command for every cluster. To scale down all host across all stamps, repeat the command for every cluster in every stamp.

Here's an example of scaling down the `hydro-processor` deployment in the `general-3-va3-iad` cluster in the production stamp.

```bash
kubectl --context general-3-va3-iad scale --replicas=0 -n licensify-production deployment/hydro-processor
```

To scale the deployment back up, simply change the `--replicas` flag to the desired number of replicas.

To find the correct number of replicas to use, reference the replicas value found in kube deployment config file in this repo at `config/kubernetes/<stamp>/deployments/<deployment>.yaml`.

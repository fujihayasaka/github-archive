import { AlertIcon, ArrowSwitchIcon, CheckIcon } from "@primer/octicons-react";
import { Box, BranchName, Label, Link, Octicon, PageLayout, Text, Truncate } from "@primer/react";
import { Suspense } from "react";
import { Await, defer, useAsyncValue, useLoaderData } from "react-router-dom";
import { getCorpora, getDeployAheadBehind, listStamps } from "../../api";

async function getDeployments() {
  const stamps = await listStamps();
  const corpora = await Promise.all(
    stamps.map(async (stamp) => {
      // NB: each stamp is proxied to a different admin service so we have to make N calls.
      const resp = await getCorpora(stamp);
      return {
        stamp: stamp,
        deploy_env: resp.deploy_env,
        corpora: resp.statuses,
      };
    })
  );
  // console.log(corpora);
  let m = new Map();
  for (const corpus of corpora) {
    for (const deployment of corpus.corpora) {
      if (m.has(deployment.binary_version)) {
        m.get(deployment.binary_version).push({ stamp: corpus.stamp, ...deployment });
      } else {
        m.set(deployment.binary_version, [{ stamp: corpus.stamp, ...deployment }]);
      }
    }
  }

  // console.log(m);
  let deployments = Array.from(m, ([key, value]) => ({ deployed_sha: key, environments: value }));
  const shas = deployments.map((x) => x.deployed_sha);
  const resp = await getDeployAheadBehind(shas);

  deployments = deployments.map((x, i) => {
    const s = resp.statuses[i];
    x.github_status = s;
    return x;
  });

  // console.log(deployments);
  return { deployments: deployments, head_sha: resp.head_sha };
}

export async function loader() {
  return defer({ data: getDeployments() });
}

export default function Index() {
  const { data } = useLoaderData();
  return (
    <PageLayout>
      <PageLayout.Content>
        <Suspense fallback={<div>Loading...</div>}>
          <Await resolve={data}>
            <Deployments />
          </Await>
        </Suspense>
      </PageLayout.Content>
    </PageLayout>
  );
}

function Deployments() {
  const data = useAsyncValue();
  return (
    <>
      {data.deployments
        .toSorted((a, b) => {
          if (a.deployed_sha === data.head_sha) {
            return -1;
          }
          if (b.deployed_sha === data.head_sha) {
            return 1;
          }
          if (a.deployed_sha === "") {
            return -1;
          }
          if (b.deployed_sha === "") {
            return 1;
          }
          return 0;
        })
        .map((x) => (
          <Deployment deployment={x} head_sha={data.head_sha} key={x.deployed_sha} />
        ))}
    </>
  );
}

function Deployment({ deployment, head_sha }) {
  const pr = deployment.github_status.pr;

  let title;
  if (deployment.deployed_sha === "") {
    title = (
      <Text sx={{ mb: 1 }}>
        <Octicon icon={AlertIcon} sx={{ color: "attention.fg", mr: 2 }} />
        <Text sx={{ fontSize: 2 }}>Hosts not reporting a binary version</Text>
      </Text>
    );
  } else if (deployment.deployed_sha === head_sha) {
    title = (
      <Box sx={{ display: "flex", alignItems: "center", mb: 1 }}>
        <Octicon icon={CheckIcon} sx={{ mr: 2, color: "success.fg" }} />
        <BranchName as="span" sx={{ mr: 2 }}>
          main
        </BranchName>
        <Truncate inline expandable title={deployment.deployed_sha} sx={{ maxWidth: 70, pb: 1 }}>
          <code>{deployment.deployed_sha}</code>
        </Truncate>
      </Box>
    );
  } else {
    title = (
      <Box sx={{ display: "flex", alignItems: "center" }}>
        <Octicon icon={ArrowSwitchIcon} sx={{ mr: 2, color: "fg.subtle" }} />
        {pr && (
          <BranchName as="span" sx={{ mr: 2 }}>
            {pr.ref}
          </BranchName>
        )}
        <Link
          href={`https://github.com/github/blackbird/compare/${deployment.deployed_sha}...${head_sha}`}
          sx={{ pb: 1, textDecoration: "underline"}}
        >
          <code>
            {deployment.deployed_sha.slice(0, 6)}...{head_sha.slice(0, 6)}
          </code>
        </Link>
      </Box>
    );
  }

  // Collapse up by stamp for display
  let stamps = new Map();
  for (const env of deployment.environments) {
    if (stamps.has(env.stamp)) {
      stamps.get(env.stamp).push(env);
    } else {
      stamps.set(env.stamp, [env]);
    }
  }
  return (
    <Box display="flex" flexDirection="column" sx={{ py: 3 }}>
      <Box display="flex">{title}</Box>

      {pr && (
        <Box sx={{ pb: 1, pl: 0, fontSize: 2 }}>
          <Link href={pr.html_url} sx={{ textDecoration: "underline" }} muted>
            #{pr.number}: {pr.title}
          </Link>{" "}
          <Text sx={{ color: "fg.muted" }}>
            by{" "}
            <Link
              sx={{ textDecoration: "underline" }}
              href={`https://github.com/github/blackbird/pulls/${encodeURIComponent(pr.author)}`}
              muted
            >
              @{pr.author}
            </Link>
          </Text>
        </Box>
      )}

      <Box display="flex" flexDirection="row">
        {Array.from(stamps, ([stamp, envs]) => {
          return (
            <Box key={stamp} display="flex" flexDirection="column">
              {envs.map((env) => (
                <Label key={`${env.stamp}-${env.cluster_name}`} sx={{ my: 0.5, mr: 1 }}>
                  <Text sx={{ color: "fg.subtle" }}>{env.stamp}-</Text>
                  {env.cluster_name}
                </Label>
              ))}
            </Box>
          );
        })}
      </Box>
    </Box>
  );
}

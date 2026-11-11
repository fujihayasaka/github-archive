import React from "react";
import {
  Box,
  Button,
  Checkbox,
  Flash,
  FormControl,
  Heading,
  Label,
  Link,
  Pagehead,
  PageLayout,
  Select,
  Octicon,
  Text,
  Tooltip,
  PageHeader,
  Stack,
  TextInput,
} from "@primer/react";
import { useState } from "react";
import { CheckIcon, XIcon, ClockIcon, AlertIcon, CodescanCheckmarkIcon, MarkGithubIcon } from "@primer/octicons-react";
import { useFetcher, useLoaderData, useParams } from "react-router-dom";
import { getCorpora, getRepo, getRepoById, selectCorpus, post } from "../../api";
import { getSplunkLink } from "../../components/splunk";
import { getStafftoolsLink } from "../../components/stafftools";
import { DataTable, Table } from "@primer/react/drafts";
import { corpusDisplayName } from "../../components/corpus";

export async function loader({ params }) {
  const stamp = params.stamp;
  const [repo, corpora] = await Promise.all([
    params.id ? getRepoById(stamp, params.id) : getRepo(stamp, params.owner, params.name),
    getCorpora(stamp).then((res) => {
      return res.statuses;
    }),
  ]);
  return { repo, corpora };
}

export async function action({ request, params }) {
  const data = Object.fromEntries(await request.formData());
  if (params.id) {
    data.repo_id = params.id;
  } else {
    data.repo_nwo = `${params.owner}/${params.name}`;
  }

  if (data.force_reindex && data.force_reindex === "true") {
    data.force_reindex = true;
  } else {
    delete data.force_reindex;
  }

  if (data.index_embeddings && data.index_embeddings === "true") {
    data.index_embeddings = true;
  } else {
    delete data.index_embeddings;
  }

  const method = data.rpcMethod;
  delete data.rpcMethod;
  return post(params.stamp, method, data, { useNewErrorHandling: true });
}

export default function Repo() {
  const { repo, corpora } = useLoaderData();
  const fetcher = useFetcher();
  const params = useParams();
  let servingCorpus = corpora.filter((c) => c.serving)[0];

  let failed;
  if (repo.failure) {
    failed = (
      <Flash variant="danger" sx={{ mb: 2 }}>
        <Heading as="h2" sx={{ fontSize: 2 }}>
          This repo had a permanent ingest failure
        </Heading>
        <Stack gap="none">
          <Text fontSize={1}>Failed: {repo.failure.failed_at}</Text>
          <Text fontSize={1}>{repo.failure.failure_reason}</Text>
          <Text fontSize={1}>Category: {repo.failure.failure_category}</Text>
        </Stack>
      </Flash>
    );
  } else if (
    repo.indexer_ingests &&
    repo.indexer_ingests.some((ingest) => ingest.snapshot_entries.some((entry) => entry.permanent_error))
  ) {
    failed = (
      <Flash variant="danger" sx={{ mb: 2 }}>
        <Heading as="h2" sx={{ fontSize: 2 }}>
          This repo had a permanent ingest failure
        </Heading>
        <Stack gap="none">
          {repo.indexer_ingests
            .filter((ingest) => ingest.snapshot_entries.some((entry) => entry.permanent_error !== ""))
            .map((ingest) => {
              let error = ingest.snapshot_entries.find((entry) => entry.permanent_error !== "").permanent_error;
              return (
                <Text fontSize={1}>
                  {ingest.corpus}: {error}
                </Text>
              );
            })}
        </Stack>
      </Flash>
    );
  }

  return (
    <GitHubRepo
      repo={repo}
      corpora={corpora}
      servingCorpus={servingCorpus}
      fetcher={fetcher}
      params={params}
      failed={failed}
    />
  );
}

function GitHubRepo({ repo, corpora, servingCorpus, fetcher, params, failed }) {
  const indexedEmbeddingsOnlyCorpora = corpora.filter(
    (c) =>
      c.epoch_features_only_embeddings &&
      repo.indexer_ingests &&
      repo.indexer_ingests.some((ingest) => ingest.corpus === c.corpus_name && ingest.snapshot_entries.length > 0)
  );

  if (repo.failed) {
    return (
      <PageLayout>
        <PageLayout.Content>
          <Pagehead>
            Failed to get info for{" "}
            <Link href={getStafftoolsLink(params.stamp, `${params.owner}/${params.name}`)}>
              {params.owner}/{params.name}
            </Link>
          </Pagehead>
          <Text>Error: {repo.error.msg}</Text>
        </PageLayout.Content>
      </PageLayout>
    );
  }

  return (
    <PageLayout>
      <PageLayout.Content>
        {fetcher.data && fetcher.data.flash && <Flash>{fetcher.data.flash}</Flash>}
        <PageHeader role="banner" aria-label="Title">
          <PageHeader.TitleArea>
            <PageHeader.Title>
              <Box display="flex" alignItems="center">
                <Box sx={{ ml: 1 }}>
                  <Link href={getStafftoolsLink(params.stamp, `repositories/${repo.repo_nwo}`)}>{repo.repo_nwo}</Link>
                </Box>
                <Label sx={{ ml: 2 }} size="large">
                  <Octicon icon={MarkGithubIcon} sx={{ mr: 1 }} />
                  {repo.is_public ? "public" : "private"}
                </Label>
                {repo.deleted_at && (
                  <Label sx={{ ml: 2 }} variant="danger">
                    Deleted {repo.deleted_at}
                  </Label>
                )}
              </Box>
            </PageHeader.Title>
          </PageHeader.TitleArea>
          <PageHeader.Description>
            <Stack gap="condensed">
              {repo.indexer_ingests.length === 0 && (
                <Text sx={{ mb: 2 }}>
                  <Octicon icon={AlertIcon} sx={{ color: "danger.fg", mr: 1 }} />
                  Not indexed by blackbird
                </Text>
              )}
            </Stack>
          </PageHeader.Description>
          <PageHeader.Actions>
            <Text color="fg.subtle" fontSize={1}>
              <Text sx={{ mr: 1 }}>Splunk:</Text>
              <Link
                href={getSplunkLink(
                  params.stamp,
                  `app=blackbird-ingest corpus=${servingCorpus.corpus_name} repo_id="${repo.repo_id}"`
                )}
              >
                ingest
              </Link>
              <Text sx={{ mx: 1 }}>·</Text>
              <Link
                href={getSplunkLink(
                  params.stamp,
                  `app=blackbird-query corpus=${servingCorpus.corpus_name} repo_id="${repo.repo_id}"`
                )}
              >
                lexical query
              </Link>
              <Text sx={{ mx: 1 }}>·</Text>
              <Link
                href={getSplunkLink(
                  params.stamp,
                  `app=blackbird-mw-semantic corpus=${servingCorpus.corpus_name} repo_id="${repo.repo_id}"`
                )}
              >
                semantic query
              </Link>
            </Text>
          </PageHeader.Actions>
        </PageHeader>

        <Stack gap="condensed">
          {failed}
          {repo.indexer_ingests.length > 0 && <RepoClusterStatus repo={repo} corpora={corpora} />}
          <RepoActionError data={fetcher.data} />
          <Index fetcher={fetcher} repo={repo} />
          <Probe fetcher={fetcher} corpora={corpora} servingCorpus={servingCorpus} repo={repo} stamp={params.stamp} />
          {indexedEmbeddingsOnlyCorpora.length > 0 && <DeleteEmbeddings fetcher={fetcher} />}
        </Stack>

        <Pagehead>Raw JSON</Pagehead>
        <Box>
          <pre>{JSON.stringify(repo, null, 2)}</pre>
        </Box>
      </PageLayout.Content>
    </PageLayout>
  );
}

function RepoActionError({ data }) {
  let err = data && data.failed ? data.error : null;
  if (err) {
    return (
      <Flash variant="danger" sx={{ mb: 2 }}>
        <Heading as="h2" sx={{ fontSize: 2 }}>
          <Text>{err.msg || err}</Text>
        </Heading>
      </Flash>
    );
  }
  return null;
}

function RepoActionValidation({ fetcher, rpcMethod, successMessage }) {
  const didAction = fetcher.data && fetcher.data._rpcMethod === rpcMethod;
  if (!didAction) return null;

  const isSuccess = !fetcher.data.failed;
  const isUserError = fetcher.data.failed && String(fetcher.data.code).startsWith("4");

  if (!isSuccess && !isUserError) return null;

  return (
    <FormControl.Validation variant={isSuccess ? "success" : "error"}>
      {isSuccess ? (
        <Text fontSize={1} color="success.fg">
          {successMessage}
        </Text>
      ) : (
        <Text fontSize={1}>
          {fetcher.data.error.msg || fetcher.data.error}
        </Text>
      )}
    </FormControl.Validation>
  );
}

function DeleteEmbeddings({ fetcher }) {
  return (
    <Box sx={{ pb: 2, borderBottom: "1px solid", borderColor: "border.default" }}>
      <fetcher.Form method="post">
        <input type="hidden" name="rpcMethod" value="DeleteRepoEmbeddings"></input>
        <Stack gap="condensed" direction="horizontal" align="end" justify="space-between">
          <Stack gap="none">
            <Text fontWeight="bold">Manage embeddings</Text>
            <Text color="fg.subtle" fontSize={1}>
              Remove the repo from embeddings-only clusters. Has no effect on lexical or hybrid clusters.
            </Text>
          </Stack>
          <Stack direction="horizontal" align="center">
            <FormControl>
              <RepoActionValidation
                fetcher={fetcher}
                rpcMethod="DeleteRepoEmbeddings"
                successMessage="Success!"
              />
              <Button type="submit" variant="danger">
                Delete embeddings
              </Button>
            </FormControl>
          </Stack>
        </Stack>
      </fetcher.Form>
    </Box>
  );
}

function Index({ fetcher, repo }) {
  const [forceReindex, setForceReindex] = useState(false);
  const [indexEmbeddings, setIndexEmbeddings] = useState(false);
  return (
    <Box sx={{ pb: 2, borderBottom: "1px solid", borderColor: "border.default" }}>
      <fetcher.Form method="post">
        <input type="hidden" name="rpcMethod" value="IndexRepo"></input>
        <Stack gap="condensed">
          <Stack gap="none">
            <Text fontWeight="bold">Index</Text>
            <Text color="fg.subtle" fontSize={1}>
              Queue this repository for indexing.
            </Text>
          </Stack>
          <Stack gap="condensed" direction="horizontal" align="end" justify="space-between">
            <Stack gap="condensed">
              <FormControl>
                <FormControl.Label>Force reindex</FormControl.Label>
                <Checkbox
                  aria-label="Force reindex"
                  name="force_reindex"
                  value={forceReindex}
                  checked={forceReindex}
                  onChange={(e) => setForceReindex(e.target.checked)}
                />
                <FormControl.Caption>
                  Recrawl the repo from scratch, attached to the root node and clearing any permanent errors.
                </FormControl.Caption>
              </FormControl>
              <FormControl>
                <FormControl.Label>Index Embeddings</FormControl.Label>
                <Checkbox
                  aria-label="Index Embeddings"
                  name="index_embeddings"
                  value={indexEmbeddings}
                  checked={indexEmbeddings}
                  onChange={(e) => setIndexEmbeddings(e.target.checked)}
                />
                <FormControl.Caption>
                  Queue the repo to be indexed for semantic search.
                </FormControl.Caption>
              </FormControl>
            </Stack>
            <Stack direction="horizontal" align="center">
              <FormControl>
                <RepoActionValidation
                  fetcher={fetcher}
                  rpcMethod="IndexRepo"
                  successMessage={`Success! Queued ${repo.repo_nwo} for indexing.`}
                />
              </FormControl>
              <Button type="submit">Index this repo</Button>
            </Stack>
          </Stack>
        </Stack>
      </fetcher.Form>
    </Box>
  );
}

function Probe({ fetcher, corpora, servingCorpus, repo, stamp }) {
  const [probeCorpus, setProbeCorpus] = useState(servingCorpus?.corpus_name?.toLowerCase());
  const didProbe = fetcher.data && fetcher.data._rpcMethod === "ProbeRepo";
  return (
    <Box sx={{ pb: 2, borderBottom: "1px solid", borderColor: "border.default" }}>
      <fetcher.Form method="post">
        <input type="hidden" name="rpcMethod" value="ProbeRepo"></input>
        <Stack gap="condensed">
          <Stack gap="none">
            <Text fontWeight="bold">Probe</Text>
            <Text color="fg.subtle" fontSize={1}>
              Run the completeness prober on this repository.
            </Text>
          </Stack>
          <FormControl>
            <FormControl.Label>Path</FormControl.Label>
            <TextInput aria-label="Path" name="path" />
            <FormControl.Caption>
              Optionally probe a specific path in the repo. Leave blank to probe the entire repo.
            </FormControl.Caption>
          </FormControl>
          <Stack gap="condensed" direction="horizontal" align="end" justify="space-between">
            <FormControl>
              <FormControl.Label required>Corpus</FormControl.Label>
              <Select name="corpus" value={probeCorpus} onChange={(e) => setProbeCorpus(e.target.value)}>
                {corpora
                  .filter((c) => !c.corpus_name.includes("cache"))
                  .map((c, i) => (
                    <Select.Option key={i} value={c.corpus_name.toLowerCase()}>
                      {corpusDisplayName(c)}
                    </Select.Option>
                  ))}
              </Select>
              <RepoActionValidation
                fetcher={fetcher}
                rpcMethod="ProbeRepo"
                successMessage="Success!"
              />
            </FormControl>

            <Stack direction="horizontal" align="center">
              <Button type="submit">Probe this repo</Button>
            </Stack>
          </Stack>
        </Stack>
      </fetcher.Form>

      {didProbe && !fetcher.data.failed && (
        <Box display="flex" flexDirection="column" sx={{ mt: 1 }}>
          <Text fontSize={1} color="muted.fg">
            Finished probing {repo.repo_nwo} (downsampled with {fetcher.data.num_trailing_zeros} trailing zeros):
            <br />
            {fetcher.data.verified} documents verified, {fetcher.data.extra.length} extra, {fetcher.data.missing.length}{" "}
            not indexed
            <br />
            <Link
              href={getSplunkLink(stamp, `app=blackbird-admin corpus=${probeCorpus} ${repo.repo_nwo}`, {
                earliest: "-60m@m",
                "display.events.fields": '["path","paths","msg","skip_reason"]',
              })}
            >
              Splunk logs
            </Link>
          </Text>

          {repo.is_public ? (
            <>
              {fetcher.data.extra.length > 0 && (
                <Box sx={{ mt: 2 }}>
                  <Text fontSize={1} fontWeight="bold">
                    <Octicon icon={AlertIcon} color="attention.fg" sx={{ mr: 2 }} />
                    Blackbird returned results not found in the git repo:
                  </Text>
                  <pre>
                    {fetcher.data.extra.map((e) => {
                      return `${e}\n`;
                    })}
                  </pre>
                </Box>
              )}
              {fetcher.data.missing.length > 0 && (
                <Box sx={{ mt: 2 }}>
                  <Text fontSize={1} fontWeight="bold">
                    These paths were not indexed:
                  </Text>
                  <pre>
                    {fetcher.data.missing.map((e) => {
                      return `${e}\n`;
                    })}
                  </pre>
                </Box>
              )}
            </>
          ) : (
            <Text fontSize={1} fontStyle="italic">
              Because repo is private: extra and missing path details are hidden. See splunk logs instead.
            </Text>
          )}
        </Box>
      )}
    </Box>
  );
}

function RepoClusterStatus({ repo, corpora }) {
  let data = repo.indexer_ingests
    .map((ingest, i) => {
      const corpus = selectCorpus(corpora, ingest.corpus);
      if (!corpus) {
        return null;
      }

      if (corpus.epoch_features_external_content) {
        return null;
      }

      const isIndexed =
        ingest.snapshot_entries.length > 0 && ingest.snapshot_entries.every((entry) => !entry.permanent_error);
      const isServing = ingest.snapshot_entries
        .slice(-1)
        .some((entry) => entry.entry_state === "SNAPSHOT_ENTRY_STATE_ACTIVE" && !entry.permanent_error);
      const shardOffset = parseInt(corpus.serving_offset, 10);
      const ingestOffset = parseInt(ingest.snapshot_entries.slice(-1).map((entry) => entry.serving_offset)[0] || 0, 10);
      const isServingOffset = isIndexed && shardOffset > ingestOffset;

      let inner = null;
      if (isIndexed && isServing && isServingOffset) {
        inner = <Octicon icon={CodescanCheckmarkIcon} color="success.fg" />;
      } else if (isIndexed && isServing) {
        inner = <Octicon icon={ClockIcon} color="attention.fg" />;
      } else if (isIndexed) {
        inner = <Octicon icon={AlertIcon} color="severe.fg" />;
      } else {
        inner = <Octicon icon={XIcon} color="danger.fg" />;
      }

      let diff = shardOffset - ingestOffset;
      if (diff > 0) {
        diff = `+${diff.toLocaleString()}`;
      } else {
        diff = diff.toLocaleString();
      }

      return {
        icon: inner,
        cluster: corpusDisplayName(corpus),
        serving: isServing && <Octicon icon={CheckIcon} color="subtle.fg" />,
        mode: corpus.epoch_mode,
        ingestOffset: ingestOffset.toLocaleString(),
        servingOffset: shardOffset.toLocaleString(),
        delta: diff,
      };
    })
    .filter((x) => x !== null);

  return (
    <Table.Container>
      <DataTable
        data={data}
        columns={[
          { header: "", field: "icon", width: "40px" },
          { header: "Cluster", field: "cluster" },
          { header: "Serving", field: "serving", width: "growCollapse", minWidth: "40px", maxWidth: "80px" },
          { header: "Epoch Mode", field: "mode" },
          { header: "Repo Ingest Offset", field: "ingestOffset" },
          { header: "Cluster Serving Offset", field: "servingOffset" },
          { header: "Delta", field: "delta" },
        ]}
      />
    </Table.Container>
  );
}

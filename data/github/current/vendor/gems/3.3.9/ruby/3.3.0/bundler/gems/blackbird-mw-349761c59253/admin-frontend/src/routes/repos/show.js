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
} from "@primer/react";
import { useState } from "react";
import { CheckIcon, XIcon, ClockIcon, AlertIcon } from "@primer/octicons-react";
import { useFetcher, useLoaderData, useParams, useRouteLoaderData } from "react-router-dom";
import { getCorpora, getRepo, selectCorpus, setRepo } from "../../api";
import { getSplunkLink } from "../../components/splunk";
import { getStafftoolsLink } from "../../components/stafftools";

export async function loader({ params }) {
  const stamp = params.stamp;
  const [repo, corpora] =
    await Promise.all([
      getRepo(stamp, params.owner, params.name),
      getCorpora(stamp).then((res) => {
        return res.statuses;
      })
    ]);
  return { repo, corpora };
}

export async function action({ request, params }) {
  const data = Object.fromEntries(await request.formData());
  data.repo_nwo = `${params.owner}/${params.name}`;

  if (data.force_reindex && data.force_reindex === "true") {
    data.force_reindex = true;
  } else {
    delete data.force_reindex;
  }

  const method = data.rpcMethod;
  delete data.rpcMethod;
  let res = await setRepo(params.stamp, method, data);
  res.method = method;
  return res;
}

export default function Repo() {
  const { repo, corpora } = useLoaderData();
  const fetcher = useFetcher();
  const [forceReindex, setForceReindex] = useState(false);
  const params = useParams();
  let servingCorpus = corpora.filter((c) => c.serving)[0];
  const [probeCorpus, setProbeCorpus] = useState(servingCorpus?.corpus_name?.toLowerCase());

  const didIndex = fetcher.data && fetcher.data.method === "IndexRepo";
  const didProbe = fetcher.data && fetcher.data.method === "ProbeRepo";

  let failed;
  if (repo.failure) {
    failed = (
      <Flash variant="danger" sx={{ mb: 2 }}>
        <Heading as="h2" sx={{ fontSize: 2 }}>
          This repo had a permanent ingest failure
        </Heading>
        <Box>Failed: {repo.failure.failed_at}</Box>
        <Box>{repo.failure.failure_reason}</Box>
        <Box>Category: {repo.failure.failure_category}</Box>
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
        {repo.indexer_ingests
          .filter((ingest) => ingest.snapshot_entries.some((entry) => entry.permanent_error !== ""))
          .map((ingest) => {
            let error = ingest.snapshot_entries.find((entry) => entry.permanent_error !== "").permanent_error;
            return (
              <Box>
                {ingest.corpus}: {error}
              </Box>
            );
          })}
      </Flash>
    );
  }

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
        <Pagehead>
          <Box display="flex" flexDirection="column">
            <Box>
              <Heading as="h2" sx={{ fontSize: 3 }}>
                <Box display="flex" alignItems="center">
                  <Box sx={{ ml: 1 }}>
                    <Link href={getStafftoolsLink(params.stamp, `repositories/${repo.repo_nwo}`)}>
                      {repo.repo_nwo}
                    </Link>
                  </Box>
                  <Label sx={{ ml: 2 }}>{repo.is_public ? "public" : "private"}</Label>
                  {repo.deleted_at && (
                    <Label sx={{ ml: 2 }} variant="danger">
                      Deleted {repo.deleted_at}
                    </Label>
                  )}
                </Box>
              </Heading>
            </Box>
          </Box>
        </Pagehead>

        {failed}

        <Box display="flex">
          {repo.indexer_ingests.map((ingest, i) => {
            const corpus = selectCorpus(corpora, ingest.corpus);
            if (!corpus) {
              return null;
            }

            const isIndexed =
              ingest.snapshot_entries.length > 0 && ingest.snapshot_entries.every((entry) => !entry.permanent_error);
            const isServing = ingest.snapshot_entries
              .slice(-1)
              .some((entry) => entry.entry_state === "SNAPSHOT_ENTRY_STATE_ACTIVE" && !entry.permanent_error);
            const shardOffset = parseInt(corpus.serving_offset, 10);
            const ingestOffset = parseInt(
              ingest.snapshot_entries.slice(-1).map((entry) => entry.serving_offset)[0] || 0,
              10
            );
            const isServingOffset = isIndexed && shardOffset > ingestOffset;

            let inner = null;
            if (isIndexed && isServing && isServingOffset) {
              inner = <Octicon icon={CheckIcon} color="success.fg" />;
            } else if (isIndexed && isServing) {
              inner = <Octicon icon={ClockIcon} color="attention.fg" />;
            } else if (isIndexed) {
              inner = <Octicon icon={AlertIcon} color="severe.fg" />;
            } else {
              inner = <Octicon icon={XIcon} color="danger.fg" />;
            }

            let diff = shardOffset - ingestOffset;
            if (diff > 0) {
              diff = `+${diff}`;
            }
            const tooltip = `${ingest.corpus} is serving offset: ${shardOffset}\nRepo ingested at offset: ${ingestOffset} (${diff})`;

            return (
              <Box key={`ingest-${i}`} sx={{ mr: 4 }}>
                <Tooltip aria-label={tooltip}>
                  {inner}
                  <Text color="fg.subtle" sx={{ ml: 1 }}>
                    {ingest.corpus}
                    {corpus.serving && " (serving)"}
                  </Text>
                </Tooltip>
              </Box>
            );
          })}

          {repo.indexer_ingests.length === 0 && (
            <Text sx={{ mr: 2 }}>
              <Octicon icon={AlertIcon} sx={{ color: "danger.fg", mr: 1 }} />
              Not indexed by blackbird
            </Text>
          )}

          <Box>
            <Text color="fg.subtle" ontSize={1}>
              <Text sx={{ mr: 1 }}>Splunk:</Text>
              <Link href={getSplunkLink("blackbird-ingest", servingCorpus, `repo_id="${repo.repo_id}"`, params.stamp)}>
                ingest
              </Link>
              <Text sx={{ mx: 1 }}>·</Text>
              <Link href={getSplunkLink("blackbird-query", servingCorpus, `repo_id="${repo.repo_id}"`, params.stamp)}>
                query
              </Link>
            </Text>
          </Box>
        </Box>

        <Text fontWeight="bold" display="block" sx={{ pt: 4 }}>
          Index
        </Text>
        <Text color="fg.subtle" fontSize={1} display="block" sx={{ mb: 2 }}>
          Queue a job to crawl and re-index this repository. Selecting <b>force reindex</b> will cause the repo to be
          recrawled from scratch, attached to the root node and clearing any permanent error.
        </Text>

        <Box display="flex" flexDirection="column">
          <fetcher.Form method="post">
            <input type="hidden" name="rpcMethod" value="IndexRepo"></input>
            <FormControl sx={{ mb: 2 }}>
              <FormControl.Label>Force reindex</FormControl.Label>
              <Checkbox
                aria-label="Force reindex"
                name="force_reindex"
                value={forceReindex}
                checked={forceReindex}
                onChange={(e) => setForceReindex(e.target.checked)}
              />
            </FormControl>
            <Button type="submit" sx={{ mr: 2 }}>
              Index this repo
            </Button>
            {didIndex && (
              <Text fontSize={1} color="success.fg">
                <Octicon icon={CheckIcon} /> Success! Queued {repo.repo_nwo} for indexing.
              </Text>
            )}
          </fetcher.Form>
        </Box>

        <Text fontWeight="bold" display="block" sx={{ pt: 4 }}>
          Probe
        </Text>
        <Text color="fg.subtle" fontSize={1} display="block" sx={{ mb: 2 }}>
          Run the completeness prober on this repository.
        </Text>

        <Box display="flex" sx={{ mb: 4 }}>
          <fetcher.Form method="post">
            <input type="hidden" name="rpcMethod" value="ProbeRepo"></input>
            <Box display="flex" alignItems="center">
              <Button type="submit" sx={{ mr: 1 }}>
                Probe in corpus:
              </Button>
              <FormControl display="flex" sx={{ mr: 2 }}>
                <FormControl.Label visuallyHidden>Corpus</FormControl.Label>
                <Select name="corpus" value={probeCorpus} onChange={(e) => setProbeCorpus(e.target.value)}>
                  {corpora
                    .filter((c) => !c.corpus_name.includes("cache"))
                    .map((c, i) => (
                      <Select.Option key={i} value={c.corpus_name.toLowerCase()}>
                        {c.corpus_name}
                      </Select.Option>
                    ))}
                </Select>
              </FormControl>
              {didProbe && (
                <Text fontSize={1} color="success.fg">
                  <Octicon icon={CheckIcon} /> Success!
                </Text>
              )}
            </Box>
            {didProbe && (
              <Box display="flex" flexDirection="column" sx={{ mt: 1 }}>
                <Text fontSize={1} color="muted.fg">
                  Finished probing {repo.repo_nwo} (downsampled with {fetcher.data.num_trailing_zeros} trailing zeros):
                  <br />
                  {fetcher.data.verified} documents verified, {fetcher.data.extra.length} extra,{" "}
                  {fetcher.data.missing.length} not indexed
                  <br />
                  <Link
                    href={getSplunkLink(
                      "blackbird-admin",
                      selectCorpus(corpora, probeCorpus),
                      repo.repo_nwo,
                      params.stamp,
                      { earliest: "-60m@m", "display.events.fields": '["path","paths","msg","skip_reason"]' }
                    )}
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
          </fetcher.Form>
        </Box>

        <Pagehead>Raw JSON</Pagehead>
        <Box>
          <pre>{JSON.stringify(repo, null, 2)}</pre>
        </Box>
      </PageLayout.Content>
    </PageLayout>
  );
}

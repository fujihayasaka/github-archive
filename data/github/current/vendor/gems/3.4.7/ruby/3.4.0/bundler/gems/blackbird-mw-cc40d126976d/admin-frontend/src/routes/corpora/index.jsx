import React from "react";
import {
  Box,
  Label,
  LabelGroup,
  PageLayout,
  Octicon,
  Tooltip,
  ActionList,
  Text,
  Truncate,
  Button,
} from "@primer/react";
import {
  PinIcon,
  ClockIcon,
  CheckIcon,
  AlertIcon,
  CacheIcon,
  HourglassIcon,
  HeartIcon,
  HeartFillIcon,
  CloudOfflineIcon,
  PlayIcon,
  ColumnsIcon,
} from "@primer/octicons-react";
import { Navigate, Outlet, useMatch, useParams, useResolvedPath, Link as RouterLink } from "react-router-dom";
import { corpusDisplayName, EpochMode } from "../../components/corpus";
import { getClusterHosts, getCorpora, getShardAssignments, selectCorpus } from "../../api";
import { useEffect, useState } from "react";
import useHotkey, { HOTKEY_PAUSE } from "../../keyboardShortcuts";

async function fetchAllCorpora(stamp, name) {
  const res = await getCorpora(stamp);
  const corpus = selectCorpus(res.statuses, name);
  return { stamp, name, deployEnv: res.deploy_env, corpora: res.statuses, corpus };
}

async function fetchSelectedCorpusDetails(stamp, name, offset = -1) {
  if (!name) {
    return { stamp, name, corpora: [] };
  }
  try {
    const [res, snapshot, clusterHosts] = await Promise.all([
      getCorpora(stamp),
      getShardAssignments(stamp, { corpus: name, offset: offset }),
      getClusterHosts(stamp, { corpus: name }).then((res) => new Set(res.hosts)),
    ]);

    const assignments = snapshot.failed ? [] : snapshot.host_assignments;
    const dsaHosts = new Set(assignments.map((item) => item["hostname"]));
    const extraHosts = [...clusterHosts.difference(dsaHosts).keys()];
    const missingHosts = [...dsaHosts.difference(clusterHosts).keys()];

    for (const c of res.statuses) {
      if (c.corpus_name.toLowerCase() === name.toLowerCase()) {
        c.snapshot = snapshot;
        c.extraHosts = extraHosts;
        c.missingHosts = missingHosts;
      }
    }

    const corpus = selectCorpus(res.statuses, name);

    return { stamp, name, deployEnv: res.deploy_env, corpora: res.statuses, corpus };
  } catch (e) {
    console.log(e);
    return { stamp, name, error: `error loading corpora: ${e.statusText}` };
  }
}

export default function Index() {
  const isRoot = useMatch({ path: "/stamps/:stamp/corpora", end: true });
  const { stamp, name } = useParams();
  const [data, setData] = useState({ stamp, name, corpora: [] });
  const [count, setCount] = useState(0);

  // Load the lefthand nav based on the corpora in this stamp (this is pretty fast)
  useEffect(() => {
    let ignore = false;
    fetchAllCorpora(stamp, name).then((res) => {
      if (!ignore) {
        setData(res);
      }
    });
    return () => {
      ignore = true;
    };
  }, [stamp, name]);

  // Fetch the much more expensive corpus details (including shard assignment) separately
  useEffect(() => {
    let ignore = false;
    fetchSelectedCorpusDetails(stamp, name).then((res) => {
      if (!ignore) {
        setData(res);
      }
    });
    return () => {
      ignore = true;
    };
  }, [stamp, name]);

  // Background refresh on a 5s interval
  const [pauseRefresh, setPauseRefresh] = useState(false);
  useHotkey(HOTKEY_PAUSE, () => {
    setPauseRefresh(!pauseRefresh);
    setCount(0);
  });
  useEffect(() => {
    let ignore = false;
    const delay = 5000; // refresh every 5s
    const max = 5 * 60 * 1000; // stop bg refresh after 5 mins
    const interval = setInterval(() => {
      if (count >= max) {
        setPauseRefresh(true);
        setCount(0);
      }
      if (!pauseRefresh /*&& offset === -1*/) {
        fetchSelectedCorpusDetails(stamp, name).then((res) => {
          if (!ignore) {
            setCount(count + delay);
            setData(res);
          }
        });
      }
    }, delay);
    return () => {
      ignore = true;
      clearInterval(interval);
    };
  }, [stamp, name, pauseRefresh, count]);

  if (isRoot) {
    return <Navigate replace to={`/stamps/${stamp}/corpora/blue`} />;
  }

  const getCluster = (c) => {
    if (c.cluster_name.includes("cache")) {
      return <CacheCluster key={c.cluster_name} corpus={c} />;
    } else {
      return <Cluster key={c.cluster_name} corpus={c} />;
    }
  };

  let embeddingsClusters = [];
  let embeddingsGraphClusters = [];
  let lexicalClusters = [];
  let legacyHybridClusters = [];
  let hybridClusters = [];
  for (const c of data.corpora) {
    switch (c.epoch_mode) {
      case EpochMode.LegacyHybrid:
        legacyHybridClusters.push(getCluster(c));
        break;
      case EpochMode.Embeddings:
        embeddingsClusters.push(getCluster(c));
        break;
      case EpochMode.EmbeddingsGraph:
        embeddingsGraphClusters.push(getCluster(c));
        break;
      case EpochMode.Lexical:
        lexicalClusters.push(getCluster(c));
        break;
      default:
        hybridClusters.push(getCluster(c));
        break;
    }
  }

  return (
    <PageLayout>
      <PageLayout.Pane position="start" width="large" aria-label="Secondary navigation">
        {data.corpora.length > 0 && (
          <Box>
            {pauseRefresh ? (
              <Button size="small" variant="invisible" onClick={() => setPauseRefresh(false)}>
                <Octicon size={14} icon={PlayIcon} /> Resume background refresh
              </Button>
            ) : (
              <Button size="small" variant="invisible" sx={{ color: "fg.muted" }} onClick={() => setPauseRefresh(true)}>
                <Octicon size={14} icon={ColumnsIcon} /> Pause background refresh
              </Button>
            )}
          </Box>
        )}
        <ActionList>
          {legacyHybridClusters.length > 0 && (
            <ActionList.Group>
              <ActionList.GroupHeading as="h2">Hybrid (Legacy) Clusters</ActionList.GroupHeading>
              {legacyHybridClusters}
            </ActionList.Group>
          )}
          {hybridClusters.length > 0 && (
            <ActionList.Group>
              <ActionList.GroupHeading as="h2">Hybrid Clusters</ActionList.GroupHeading>
              {hybridClusters}
            </ActionList.Group>
          )}
          {lexicalClusters.length > 0 && (
            <ActionList.Group>
              <ActionList.GroupHeading as="h2">Lexical Clusters</ActionList.GroupHeading>
              {lexicalClusters}
            </ActionList.Group>
          )}
          {embeddingsClusters.length > 0 && (
            <ActionList.Group>
              <ActionList.GroupHeading as="h2">Embeddings Clusters</ActionList.GroupHeading>
              {embeddingsClusters}
            </ActionList.Group>
          )}
          {embeddingsGraphClusters.length > 0 && (
            <ActionList.Group>
              <ActionList.GroupHeading as="h2">Embeddings (Graph) Clusters</ActionList.GroupHeading>
              {embeddingsGraphClusters}
            </ActionList.Group>
          )}
        </ActionList>
      </PageLayout.Pane>
      <PageLayout.Content>
        <Box id="detail" sx={{ pt: 2 }}>
          {data.corpus && <Outlet key={`corpus-details${stamp}-${data.corpus.cluster_name}`} context={data} />}
        </Box>
      </PageLayout.Content>
    </PageLayout>
  );
}

function Cluster({ corpus }) {
  const to = corpus.corpus_name.toLowerCase();
  const resolved = useResolvedPath(to);
  const isCurrent = useMatch({ path: resolved.pathname, end: false });

  let leadingVisual = null;
  if (corpus.pinned_serving_ts && corpus.serving_ts <= corpus.pinned_serving_ts) {
    leadingVisual = (
      <Tooltip aria-label="Pinned" direction="e">
        <Octicon icon={PinIcon} sx={{ color: corpus.serving ? "success.fg" : "accent.fg" }} />
      </Tooltip>
    );
  } else if (corpus.pinned_serving_ts) {
    leadingVisual = (
      <Tooltip aria-label="Pinning…" direction="e">
        <Octicon icon={ClockIcon} sx={{ color: corpus.serving ? "danger.fg" : "attention.fg" }} />
      </Tooltip>
    );
  } else if (corpus.serving) {
    const ok = corpus.indexing && corpus.ingest_mode === "Incremental";
    leadingVisual = <Octicon icon={CheckIcon} sx={{ color: ok ? "success.fg" : "attention.fg" }} />;
  } else if (corpus.index_version === 0) {
    leadingVisual = (
      <Tooltip aria-label="No index loaded" direction="e">
        <Octicon icon={AlertIcon} sx={{ color: "attention.fg" }} />
      </Tooltip>
    );
  } else if (corpus.indexing && corpus.ingest_mode !== "Incremental") {
    leadingVisual = <Octicon icon={HourglassIcon} />;
  }

  return (
    <ActionList.LinkItem as={RouterLink} to={to} active={isCurrent}>
      {corpusDisplayName(corpus)}
      <ActionList.LeadingVisual>{leadingVisual}</ActionList.LeadingVisual>
      <ActionList.TrailingVisual>
        <LabelGroup>
          <Label variant={corpus.serving ? "success" : "secondary"}>{corpus.serving ? "Serving" : "Not serving"}</Label>
          <StateLabel corpus={corpus} />
        </LabelGroup>
      </ActionList.TrailingVisual>
      <ActionList.Description variant="block">
        <Box sx={{ display: "flex", justifyContent: "space-between" }}>
          <Box
            sx={{
              display: "flex",
              flexDirection: "column",
              justifyContent: "space-between",
            }}
          >
            <Text>
              e{corpus.epoch_id} v{corpus.index_version}
              <br />
              {corpus.cache_cluster}
              <br />
            </Text>
          </Box>
          <IndexingLabel corpus={corpus} />
        </Box>
        <Box
          sx={{
            display: "flex",
            justifyContent: "space-between",
            width: "100%",
            alignItems: "baseline",
          }}
        >
          <Truncate inline title={corpus.binary_version} sx={{ maxWidth: 65 }}>
            <Text sx={{ fontFamily: "mono" }}>{corpus.binary_version}</Text>
          </Truncate>
          <HealthBar score={corpus.health_score} />
        </Box>
      </ActionList.Description>
    </ActionList.LinkItem>
  );
}

function StateLabel(corpus) {
  const isStale = corpus.serving && parseInt(corpus.staleness_seconds, 10) > 60 * 60; // 1 hr
  return isStale ? <Label variant="attention">Stale</Label> : undefined;
}

function HealthBar({ score }) {
  const full = (key) => <Octicon key={key} icon={HeartFillIcon} sx={{ color: "danger.emphasis", ml: 1 }} />;
  const empty = (key) => <Octicon key={key} icon={HeartIcon} sx={{ color: "danger.emphasis", ml: 1 }} />;
  let items;
  if (score < 0.1) {
    items = [empty(0), empty(1), empty(2)];
  } else if (score < 0.5) {
    items = [full(0), empty(1), empty(2)];
  } else if (score < 0.8) {
    items = [full(0), full(1), empty(2)];
  } else {
    items = [full(0), full(1), full(2)];
  }
  return (
    <Box sx={{ display: "flex", alignItems: "center" }}>
      <Tooltip aria-label={score} direction="w">
        <Text sx={{ color: "fg.subtle" }}>{(score * 100).toFixed(1)}%</Text>
      </Tooltip>
      {items}
    </Box>
  );
}

function CacheCluster({ corpus }) {
  const to = corpus.corpus_name.toLowerCase();
  const resolved = useResolvedPath(to);
  const isCurrent = useMatch({ path: resolved.pathname, end: false });
  let leadingVisual = <Octicon icon={CacheIcon} />;
  if (corpus.index_version === 0) {
    leadingVisual = (
      <Tooltip aria-label="No index loaded" direction="e">
        <Octicon icon={AlertIcon} sx={{ color: "attention.fg" }} />
      </Tooltip>
    );
  }

  return (
    <ActionList.LinkItem as={RouterLink} to={to} active={isCurrent}>
      {corpus.cluster_name}
      <ActionList.LeadingVisual>{leadingVisual}</ActionList.LeadingVisual>
      <ActionList.Description variant="block">
        {corpus.active_epoch ? (
          <Text sx={{ mr: 1 }}>e{corpus.epoch_id}</Text>
        ) : (
          <Tooltip aria-label="This epoch is no longer active" direction="e">
            <Text sx={{ mr: 1, color: "danger.fg" }}>
              <Octicon icon={CloudOfflineIcon} /> e{corpus.epoch_id}
            </Text>
          </Tooltip>
        )}
        v{corpus.index_version}
        <br />
        <Truncate inline title={corpus.binary_version} sx={{ maxWidth: 65 }}>
          <Text sx={{ fontFamily: "mono" }}>{corpus.binary_version}</Text>
        </Truncate>
        <br />
      </ActionList.Description>
    </ActionList.LinkItem>
  );
}

function IndexingLabel({ corpus }) {
  let variant = "secondary";
  if (corpus.indexing) {
    switch (corpus.ingest_mode) {
      case "Backfill":
      case "BackfillCatchup":
      case "IncrementalTransition":
        variant = "accent";
        break;
      case "Incremental":
        variant = "success";
        break;
      case "Aborted":
        variant = "danger";
        break;
      default:
        variant = undefined;
    }
  }
  return <Label variant={variant}>{corpus.indexing ? `Indexing (${corpus.ingest_mode})` : "Not indexing"}</Label>;
}

import {
  Box,
  Label,
  LabelGroup,
  Link,
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
  LinkExternalIcon,
} from "@primer/octicons-react";
import { Navigate, Outlet, useMatch, useParams, useResolvedPath, Link as RouterLink, useSearchParams } from "react-router-dom";
import { corpusDisplayName, friendlyEpochMode } from "../../components/corpus";
import { getClusterHosts, getCorpora, getShardAssignments, selectCorpus } from "../../api";
import { useEffect, useState } from "react";
import useHotkey, { HOTKEY_PAUSE } from "../../keyboardShortcuts";

async function fetchAllCorpora(stamp, name) {
  const res = await getCorpora(stamp);
  const corpus = selectCorpus(res.statuses, name);
  return { stamp, name, deployEnv: res.deploy_env, corpora: res.statuses, corpus, epochModes: res.epoch_modes };
}

async function fetchSelectedCorpusDetails(stamp, name, offset = -1) {
  if (!name) {
    return { stamp, name, corpora: [] };
  }
  try {
    const [res, snapshot, clusterHostsResp] = await Promise.all([
      getCorpora(stamp),
      getShardAssignments(stamp, { corpus: name, offset: offset }),
      getClusterHosts(stamp, { corpus: name }),
    ]);

    const assignments = snapshot.failed ? [] : snapshot.host_assignments;
    const dsaHosts = new Set(assignments.map((item) => item["hostname"]));
    const clusterHosts = new Set(clusterHostsResp.hosts);
    const availabilityZone = clusterHostsResp.availability_zone;
    const vmSize = clusterHostsResp.vm_size;
    const region = clusterHostsResp.region;
    const provisionedHosts = clusterHostsResp.hosts.length;
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

    return {
      stamp,
      name,
      deployEnv: res.deploy_env,
      corpora: res.statuses,
      corpus,
      epochModes: res.epoch_modes,
      availabilityZone: availabilityZone,
      region: region,
      vmSize: vmSize,
      provisionedHosts: provisionedHosts,
    };
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
  const [searchParams] = useSearchParams();
  let offset = parseInt(searchParams.get("offset"), 10) || -1;

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
    fetchSelectedCorpusDetails(stamp, name, offset).then((res) => {
      if (!ignore) {
        setData(res);
      }
    });
    return () => {
      ignore = true;
    };
  }, [stamp, name, offset]);

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
      if (!pauseRefresh && offset !== -1) {
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

  let clusters = {};
  for (const c of data.corpora) {
    clusters[c.epoch_mode] ||= [];
    clusters[c.epoch_mode].push(getCluster(c));
  }

  return (
    <PageLayout>
      <PageLayout.Pane position="start" width="large" sticky aria-label="Secondary navigation">
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
          {Object.entries(clusters).map(([epoch_mode, clusters]) => {
            return (
              <ActionList.Group key={epoch_mode}>
                <ActionList.GroupHeading as="h2">{friendlyEpochMode(epoch_mode)} Clusters</ActionList.GroupHeading>
                {clusters}
              </ActionList.Group>
            );
          })}
        </ActionList>
      </PageLayout.Pane>
      <PageLayout.Content>
        <Box id="detail">
          {data.corpus && <Outlet key={`corpus-details${stamp}-${data.corpus.cluster_name}`} context={data} />}
        </Box>
      </PageLayout.Content>
    </PageLayout>
  );
}

export function ServingIndicator({ corpus }) {
  if (!corpus) return null;

  if (corpus.pinned_serving_ts && corpus.serving_ts <= corpus.pinned_serving_ts) {
    return (
      <Tooltip aria-label="Pinned" direction="e">
        <Octicon icon={PinIcon} sx={{ color: corpus.serving ? "success.fg" : "accent.fg" }} />
      </Tooltip>
    );
  } else if (corpus.pinned_serving_ts) {
    return (
      <Tooltip aria-label="Pinning…" direction="e">
        <Octicon icon={ClockIcon} sx={{ color: corpus.serving ? "danger.fg" : "attention.fg" }} />
      </Tooltip>
    );
  } else if (corpus.serving) {
    const ok = corpus.indexing && corpus.ingest_mode === "Incremental";
    return <Octicon icon={CheckIcon} sx={{ color: ok ? "success.fg" : "attention.fg" }} />;
  } else if (corpus.index_version === 0) {
    return (
      <Tooltip aria-label="No index loaded" direction="e">
        <Octicon icon={AlertIcon} sx={{ color: "attention.fg" }} />
      </Tooltip>
    );
  } else if (corpus.indexing && corpus.ingest_mode !== "Incremental") {
    return <Octicon icon={HourglassIcon} />;
  }
  return null;
}

function Cluster({ corpus }) {
  const to = corpus.corpus_name.toLowerCase();
  const resolved = useResolvedPath(to);
  const isCurrent = useMatch({ path: resolved.pathname, end: false });

  return (
    <ActionList.LinkItem as={RouterLink} to={to} active={isCurrent}>
      {corpusDisplayName(corpus)}
      <ActionList.LeadingVisual>
        <ServingIndicator corpus={corpus} />
      </ActionList.LeadingVisual>
      <ActionList.TrailingVisual>
        <IndexingLabel corpus={corpus} />
      </ActionList.TrailingVisual>
      <ActionList.Description variant="block">
        {corpus.cache_cluster}
        <Box display="flex" justifyContent="space-between" alignItems="baseline">
          <BuildInfo corpus={corpus} />
          <HealthBar score={corpus.health_score} />
        </Box>
      </ActionList.Description>
    </ActionList.LinkItem>
  );
}

export function HealthBar({ score }) {
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

export function BuildInfo({ corpus }) {
  return (
    <Box>
      <Truncate inline title={corpus.binary_version} sx={{ maxWidth: 65 }}>
        <Text sx={{ fontFamily: "mono" }}>{corpus.binary_version || "unknown… "}</Text>
      </Truncate>
      <RelativeBuildDaysAgo corpus={corpus} />
    </Box>
  );
}

export function BuildDiffLink({ corpus }) {
  if (!corpusHasBuildTS({ corpus })) {
    return "N/A";
  }
  const compareUrl = (corpus.binary_version && corpus.binary_version !== "")
    ? `https://github.com/github/blackbird/compare/${corpus.binary_version}...dev`
    : "";
  return (
    <Box>
      {compareUrl && compareUrl !== "" && (
        <Link href={compareUrl} sx={{ textDecoration: "underline" }} muted>
          {buildDate(corpus) + ` (${RelativeBuildDaysAgo({ corpus })})`}
        </Link>
      )}
      {diffInDays(corpus.build_ts) > 7 && (
        <Tooltip aria-label="This build is over a week old" direction="w">
          <Octicon icon={AlertIcon} sx={{ color: "attention.fg" }} />
        </Tooltip>
      )}
    </Box>
  );
}

export function BuildShaLink({ corpus }) {
  if (!corpusHasBuildTS({ corpus })) {
    return <Text sx={{ color: "fg.muted" }}>N/A</Text>;
  }
  const compareUrl = (corpus.binary_version && corpus.binary_version !== "")
    ? `https://github.com/github/blackbird/compare/${corpus.binary_version}...dev`
    : "";
  const shortSha = corpus.binary_version ? corpus.binary_version.slice(0, 7) : "unknown";
  const buildInfo = `${buildDate(corpus)} (${RelativeBuildDaysAgo({ corpus })})`;
  const linkText = `${shortSha} ${buildInfo}`;
  return (
    <Box sx={{ display: "inline-flex", alignItems: "center", gap: 1 }}>
      {compareUrl ? (
        <Link href={compareUrl}>
          <Text sx={{ fontFamily: "mono" }}>{shortSha}</Text> {buildInfo}
          <Octicon icon={LinkExternalIcon} sx={{ ml: 1 }} />
        </Link>
      ) : (
        <Text sx={{ color: "fg.muted" }}>{linkText}</Text>
      )}
      {diffInDays(corpus.build_ts) > 7 && (
        <Tooltip aria-label="This build is over a week old" direction="w">
          <Octicon icon={AlertIcon} sx={{ color: "attention.fg" }} />
        </Tooltip>
      )}
    </Box>
  );
}

export function buildDate(corpus) {
  if (!corpus || !corpus.build_ts || corpus.build_ts === "-62135596800000") {
    return "N/A";
  }

  const buildDate = new Date(Number(corpus.build_ts));
  return new Intl.DateTimeFormat("en-CA").format(buildDate); // 'en-CA' provides YYYY-MM-DD
}

function RelativeBuildDaysAgo({ corpus }) {
  // Return "N/A" if the build timestamp is not set or is the unix milliseconds
  // before the epoch that maps to Golang's time.Time.UnixMilli() zero value.
  if (!corpusHasBuildTS({ corpus })) {
    return "N/A";
  }

  const formatter = new Intl.RelativeTimeFormat("en", { numeric: "auto", style: "narrow" });

  return formatter.format(diffInDays(corpus.build_ts), "day");
}

function corpusHasBuildTS({ corpus }) {
  if (!corpus || !corpus.build_ts || corpus.build_ts === "-62135596800000") {
    return false;
  }
  return true;
}

function diffInDays(build_ts) {
  const buildDate = new Date(Number(build_ts));
  const now = new Date();
  const diffInMs = buildDate - now;
  return Math.round(diffInMs / (1000 * 60 * 60 * 24)); // Convert to days
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
      <ActionList.TrailingVisual>
        {corpus.active_epoch ? (
          <Label variant="secondary">e{corpus.epoch_id}</Label>
        ) : (
          <Tooltip aria-label="This epoch is no longer active" direction="w">
            <Label variant="danger">
              e{corpus.epoch_id} <Octicon icon={CloudOfflineIcon} sx={{ ml: 1 }} />
            </Label>
          </Tooltip>
        )}
      </ActionList.TrailingVisual>
      <ActionList.Description variant="block">
        <BuildInfo corpus={corpus} />
      </ActionList.Description>
    </ActionList.LinkItem>
  );
}

export function IndexingLabel({ corpus }) {
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

  let x = "secondary";
  if (corpus.serving) {
    x = "success";
  }
  return (
    <LabelGroup>
      <Label variant={variant}>{corpus.indexing ? `${corpus.ingest_mode}` : "Not indexing"}</Label>
      <Label variant={x}>e{corpus.epoch_id}</Label>
    </LabelGroup>
  );
}

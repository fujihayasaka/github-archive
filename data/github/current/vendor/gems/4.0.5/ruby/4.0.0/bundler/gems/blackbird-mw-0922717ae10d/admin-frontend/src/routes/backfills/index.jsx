import { useLoaderData, useFetcher, Link as RouterLink, useParams, useNavigate, redirect } from "react-router-dom";
import { useState } from "react";
import { listStamps, selectCorpus, getCorpora, post } from "../../api";
import { StackIcon, CheckIcon, LinkExternalIcon, CloudOfflineIcon } from "@primer/octicons-react";
import {
  Button,
  Checkbox,
  CheckboxGroup,
  PageLayout,
  Box,
  Link,
  Heading,
  FormControl,
  Text,
  Flash,
  Octicon,
  Label,
  Tooltip,
  Select,
} from "@primer/react";
import { HealthBar, BuildShaLink, IndexingLabel, ServingIndicator } from "../corpora/index";

function StampDetails({ corpusData }) {
  if (!corpusData) {
    return <Text sx={{ fontSize: 0, color: "fg.muted", fontStyle: "italic" }}>No data available</Text>;
  }

  const cacheEpochId = corpusData._cacheClusterEpochId;
  const cacheEpochActive = corpusData._cacheClusterActiveEpoch;

  return (
    <Box sx={{ display: "flex", flexWrap: "wrap", gap: 2, fontSize: 0, color: "fg.muted", mt: 1, alignItems: "center" }}>
      <Box sx={{ display: "flex", alignItems: "center", gap: 1 }}>
        <ServingIndicator corpus={corpusData} />
        <HealthBar score={corpusData.health_score || 0} />
      </Box>
      <Box sx={{ display: "flex", alignItems: "center", gap: 1 }}>
        <Text sx={{ color: "fg.muted" }}>{corpusData.cache_cluster}</Text>
        {cacheEpochId !== null && cacheEpochId !== undefined && (
          cacheEpochActive ? (
            <Label size="small" variant="secondary">e{cacheEpochId}</Label>
          ) : (
            <Tooltip aria-label="This epoch is no longer active on the cache cluster" direction="e">
              <Label size="small" variant="danger">
                e{cacheEpochId} <Octicon icon={CloudOfflineIcon} sx={{ ml: 1 }} />
              </Label>
            </Tooltip>
          )
        )}
      </Box>
      <Box sx={{ display: "flex", alignItems: "center", gap: 1, fontSize: 0 }}>
        <BuildShaLink corpus={corpusData} />
      </Box>
      <Text sx={{ color: "fg.muted" }}>•</Text>
      <Link
        as={RouterLink}
        to={`/stamps/${corpusData._stamp}/corpora/${corpusData.corpus_name?.toLowerCase()}`}
        sx={{ fontSize: 0 }}
      >
        View more
      </Link>
    </Box>
  );
}

export async function action({ request }) {
  const formData = await request.formData();
  const stamps = formData.getAll("stamps");
  const cluster = formData.get("cluster");
  const corpusName = formData.get("corpus");

  if (!stamps || stamps.length === 0) {
    return { error: "No stamps selected" };
  }

  const results = await Promise.allSettled(
    stamps.map(async (stamp) => {
      const corpora = await getCorpora(stamp);
      const corpusStatus = selectCorpus(corpora.statuses, corpusName);

      return post(
        stamp,
        "BeginBackfillCorpus",
        {
          corpus: corpusName,
          mst_cache_cluster: corpusStatus.cache_cluster,
          epoch_mode: corpusStatus.epoch_mode,
          num_shards: corpusStatus.num_shards,
          reason: `Bulk backfill from admin UI (${new Date().toDateString()})`,
        },
        { useNewErrorHandling: true },
      );
    }),
  );

  const failures = results.filter((r) => r.status === "rejected").map((r) => r.reason?.toString() || "Unknown error");
  const successes = results.filter((r) => r.status === "fulfilled").length;

  return { success: true, count: successes, failures };
}

export async function loader({ params }) {
  // Check for redirect before making any async calls to avoid running them twice
  if (!params.cluster) {
    return redirect("/backfills/eta");
  }

  const { stamps = [] } = await listStamps();

  const results = await Promise.allSettled(
    stamps.filter((s) => s !== "dotcom").map((stamp) => getCorpora(stamp).then((res) => ({ stamp, corpora: res }))),
  );

  const grouped = {};

  for (const result of results) {
    if (result.status === "rejected") {
      console.warn("Failed to load stamp:", result.reason);
      continue;
    }

    const { stamp, corpora } = result.value;
    if (!corpora?.statuses) continue;

    // Build a map of cache clusters by name for this stamp
    const cacheClusterMap = {};
    for (const corpusStatus of corpora.statuses) {
      const cluster = (corpusStatus.cluster_name || "").toLowerCase();
      if (cluster.startsWith("cache")) {
        cacheClusterMap[cluster] = corpusStatus;
      }
    }

    for (const corpusStatus of corpora.statuses) {
      const cluster = (corpusStatus.cluster_name || "").toLowerCase();
      const corpus = (corpusStatus.corpus_name || "").toLowerCase();

      if (cluster.startsWith("zeta") || cluster.startsWith("eta")) {
        if (!grouped[cluster]) {
          grouped[cluster] = { corpus, stamps: {} };
        }
        // Find the cache cluster this corpus references and get its epoch
        const cacheClusterName = (corpusStatus.cache_cluster || "").toLowerCase();
        const cacheClusterData = cacheClusterMap[cacheClusterName];
        // Store the full corpus status with the stamp name and cache cluster epoch attached
        grouped[cluster].stamps[stamp] = {
          ...corpusStatus,
          _stamp: stamp,
          _cacheClusterEpochId: cacheClusterData?.epoch_id,
          _cacheClusterActiveEpoch: cacheClusterData?.active_epoch,
        };
      }
    }
  }

  const clusters = {};
  for (const [key, val] of Object.entries(grouped)) {
    const stampNames = Object.keys(val.stamps).sort();
    clusters[key] = {
      corpus: val.corpus,
      stamps: stampNames,
      stampDetails: val.stamps,
    };
  }

  // Redirect to first cluster if the specified cluster doesn't exist in data
  const clusterNames = Object.keys(clusters).sort();
  if (!clusters[params.cluster]) {
    const defaultCluster = clusterNames[0];
    if (defaultCluster) {
      return redirect(`/backfills/${defaultCluster}`);
    }
  }

  return { clusters };
}

function BackfillGroup({ cluster, corpus, stamps, stampDetails }) {
  const fetcher = useFetcher();
  const isSubmitting = fetcher.state !== "idle";
  const data = fetcher.data;

  const [selectedStamps, setSelectedStamps] = useState([]);
  const [showValidation, setShowValidation] = useState(false);

  const toggleStamp = (stamp) => {
    let newSelection;
    if (selectedStamps.includes(stamp)) {
      newSelection = selectedStamps.filter((s) => s !== stamp);
    } else {
      newSelection = [...selectedStamps, stamp];
    }
    setSelectedStamps(newSelection);
    if (newSelection.length > 0) setShowValidation(false);
  };

  const allSelected = stamps.length > 0 && selectedStamps.length === stamps.length;
  const toggleSelectAll = () => {
    if (allSelected) {
      setSelectedStamps([]);
    } else {
      setSelectedStamps(stamps);
      setShowValidation(false);
    }
  };

  const handleSubmit = (e) => {
    if (selectedStamps.length === 0) {
      e.preventDefault();
      setShowValidation(true);
    }
  };

  return (
    <Box sx={{ mb: 4 }}>
      {data && data.failures && data.failures.length > 0 && (
        <Flash variant="danger" sx={{ mb: 2 }}>
          Failed to backfill {data.failures.length} stamps: {data.failures.join(", ")}
        </Flash>
      )}
      {data && data.error && (
        <Flash variant="danger" sx={{ mb: 2 }}>
          {data.error}
        </Flash>
      )}
      <fetcher.Form method="post" onSubmit={handleSubmit}>
        <input type="hidden" name="cluster" value={cluster} />
        <input type="hidden" name="corpus" value={corpus} />
        <CheckboxGroup>
          <Box sx={{ display: "flex", alignItems: "center", mb: 2 }}>
            <Button type="submit" leadingVisual={StackIcon} variant="danger">
              {isSubmitting ? "Backfilling..." : `Backfill ${cluster} in ${selectedStamps.length} stamp${selectedStamps.length !== 1 ? "s" : ""}`}
            </Button>
            {data && data.success && (
              <Text fontSize={1} color="success.fg" sx={{ ml: 2 }}>
                <Octicon icon={CheckIcon} /> Successfully triggered backfill for {data.count} stamps.
              </Text>
            )}
          </Box>
          {showValidation && (
            <Text sx={{ fontSize: 0, color: "danger.fg", mb: 2 }}>At least one stamp must be selected</Text>
          )}
          <Box sx={{ mb: 2 }}>
            <FormControl>
              <Checkbox checked={allSelected} onChange={toggleSelectAll} />
              <FormControl.Label>{allSelected ? "Deselect all" : "Select all"}</FormControl.Label>
            </FormControl>
          </Box>
          <Box display="flex" flexDirection="column" sx={{ gap: 2, mb: 2 }}>
            {stamps.length > 0 ? (
              stamps.map((stamp) => (
                <Box key={stamp} sx={{ borderBottom: "1px solid", borderColor: "border.muted", pb: 2 }}>
                  <Box sx={{ display: "flex", alignItems: "center", gap: 2, flexWrap: "wrap" }}>
                    <FormControl>
                      <Checkbox
                        value={stamp}
                        name="stamps"
                        checked={selectedStamps.includes(stamp)}
                        onChange={() => toggleStamp(stamp)}
                      />
                      <FormControl.Label sx={{ fontWeight: "semibold" }}>
                        {stamp}
                      </FormControl.Label>
                    </FormControl>
                    <IndexingLabel corpus={stampDetails[stamp]} />
                  </Box>
                  <Box sx={{ ml: 4 }}>
                    <StampDetails corpusData={stampDetails[stamp]} />
                  </Box>
                </Box>
              ))
            ) : (
              <Text as="span" sx={{ color: "fg.subtle" }}>
                <em>No stamps found</em>
              </Text>
            )}
          </Box>
        </CheckboxGroup>
      </fetcher.Form>
    </Box>
  );
}

export default function BackfillIndex() {
  const { clusters } = useLoaderData();
  const clusterNames = Object.keys(clusters).sort();
  const { cluster: selectedCluster } = useParams();
  const navigate = useNavigate();

  const handleClusterChange = (e) => {
    navigate(`/backfills/${e.target.value}`);
  };

  const currentCluster = clusters[selectedCluster];

  return (
    <PageLayout>
      <PageLayout.Content>
        <Box>
          <FormControl sx={{ mb: 3 }}>
            <FormControl.Label>Cluster</FormControl.Label>
            <Select value={selectedCluster} onChange={handleClusterChange}>
              {clusterNames.map((name) => (
                <Select.Option key={name} value={name}>
                  {name}/{clusters[name].corpus}
                </Select.Option>
              ))}
            </Select>
          </FormControl>
          {currentCluster && (
            <BackfillGroup
              key={selectedCluster}
              cluster={selectedCluster}
              corpus={currentCluster.corpus}
              stamps={currentCluster.stamps}
              stampDetails={currentCluster.stampDetails}
            />
          )}
        </Box>
      </PageLayout.Content>
      <PageLayout.Pane position="end">
        <Box sx={{ display: "flex", flexDirection: "column", gap: 2 }}>
          <Heading as="h3" sx={{ fontSize: 1 }}>Resources</Heading>
          <Link href="https://app.datadoghq.com/dashboard/9e5-gws-xwn/blackbird-cluster-health-breakdown?fromUser=false&refresh_mode=sliding&from_ts=1760915046060&to_ts=1761001446060&live=true">
            Cluster Health Dashboard
            <Octicon icon={LinkExternalIcon} sx={{ ml: 1 }} />
          </Link>
          <Link href="https://github.com/github/blackbird/blob/dev/docs/runbooks/operations/backfill-branch.md">
            Runbook
            <Octicon icon={LinkExternalIcon} sx={{ ml: 1 }} />
          </Link>
        </Box>
      </PageLayout.Pane>
    </PageLayout>
  );
}

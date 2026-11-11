import { useLoaderData } from "react-router-dom";
import { getCorpora, getFileset, getFilesetById, selectCorpus } from "../../api";
import { Box, Flash, Label, Octicon, Pagehead, PageHeader, PageLayout, Text } from "@primer/react";
import {
  AlertIcon,
  CheckIcon,
  ClockIcon,
  CodescanCheckmarkIcon,
  FileDirectorySymlinkIcon,
  XIcon,
} from "@primer/octicons-react";
import { corpusDisplayName } from "../../components/corpus";
import { DataTable, Table } from "@primer/react/drafts";

export async function loader({ params }) {
  const stamp = params.stamp;
  const [fileset, corpora] = await Promise.all([
    params.id ? getFilesetById(stamp, params.id) : getFileset(stamp, params.owner, params.name),
    getCorpora(stamp).then((res) => {
      return res.statuses;
    }),
  ]);
  return { fileset, corpora };
}

export async function action({ request, params }) {}

export default function Fileset() {
  const { fileset, corpora } = useLoaderData();

  let flash;
  if (fileset.failure) {
    flash = (
      <Flash variant="danger" sx={{ mb: 2 }}>
        <Heading as="h2" sx={{ fontSize: 2 }}>
          This fileset had a permanent ingest failure
        </Heading>
      </Flash>
    );
  } else if (
    fileset.indexer_ingests &&
    fileset.indexer_ingests.some((ingest) => ingest.snapshot_entries.some((entry) => entry.permanent_error))
  ) {
    flash = (
      <Flash variant="danger" sx={{ mb: 2 }}>
        <Heading as="h2" sx={{ fontSize: 2 }}>
          This fileset had a permanent ingest failure
        </Heading>
        <Stack gap="none">
          {fileset.indexer_ingests
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

  if (fileset.failed) {
    return (
      <PageLayout>
        <PageLayout.Content>
          <Pagehead>
            Failed to get info for {params.owner}/{params.name} (params.id)
          </Pagehead>
          <Text>Error: {fileset.error.msg}</Text>
        </PageLayout.Content>
      </PageLayout>
    );
  }

  return <FilesetDetails fileset={fileset} corpora={corpora} />;
}

function FilesetDetails({ fileset, corpora }) {
  let data = fileset.indexer_ingests
    .map((ingest, i) => {
      const corpus = selectCorpus(corpora, ingest.corpus);
      if (!corpus) {
        return null;
      }

      if (!corpus.epoch_features_external_content) {
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
    <PageLayout>
      <PageLayout.Content>
        <Table.Container>
          <PageHeader role="banner" aria-label="Title">
            <PageHeader.TitleArea>
              <PageHeader.Title>
                <Text>{fileset.fileset}</Text>
                <Label sx={{ ml: 2 }} size="large">
                  <Octicon icon={FileDirectorySymlinkIcon} sx={{ mr: 1 }} />
                  external
                </Label>
              </PageHeader.Title>
            </PageHeader.TitleArea>
          </PageHeader>

          <DataTable
            data={data}
            columns={[
              { header: "", field: "icon", width: "40px" },
              { header: "Cluster", field: "cluster" },
              { header: "Serving", field: "serving", width: "growCollapse", minWidth: "40px", maxWidth: "80px" },
              { header: "Epoch Mode", field: "mode" },
              { header: "Fileset Ingest Offset", field: "ingestOffset" },
              { header: "Cluster Serving Offset", field: "servingOffset" },
              { header: "Delta", field: "delta" },
            ]}
          />
        </Table.Container>
        <Pagehead>Raw JSON</Pagehead>
        <Box>
          <pre>{JSON.stringify(fileset, null, 2)}</pre>
        </Box>
      </PageLayout.Content>
    </PageLayout>
  );
}
